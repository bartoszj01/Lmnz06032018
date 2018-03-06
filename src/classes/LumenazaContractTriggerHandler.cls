/**
 * LumenazaContractTriggerHandler
 *
 * Changelog
 * ---------
 *
 * v1.9.0 (MSB 2017-12-20)
 * - Deactivated calling of saveVoucherCodeAsBonus() (SOBCRM-1123)
 *
 * v1.8.0 (DUR 2017-12-19)
 * - Handle Account's CustomerNoDatev__c by AccountService
 *
 * v1.7.0 (MSB 2017-06-19)
 * - Basic Lumenaza sync requirements are now checked by formula field
 *   Contract.IsValidForLumenazaSync__c
 *
 * v1.6.1 (MSB 2017-03-24)
 * - Fix: Set CustomerNoDatev__c in all related Accounts independent of
 *   the Contract's acitvation status (SOBCRM-912)
 * - Fix: Did NOT validate LumenazaApi.initUpsert(lumenazaContractsToUpsert) to FALSE so
 *   no error was raised from LumenazaContract.validate()
 *
 * v1.6.0 (DUR 2017-02-21)
 * - SOBCRM-803 - Bonus should not be created for Type 'sonnenbatterieCity-DE'
 *
 * v1.5.1 (MSB 2016-12-21)
 * - Fix: If BankData relation was NULL but bank account relevant fields were
 *   set all fields were set to NULL. Now they are only set to NULL if BankData
 *   relation changed from NOT NULL to NULL
 *
 * v1.5.0 (MSB 2016-12-20)
 * - Added setBankDataFromRelatedBankData() on insert (SOBCRM-754)
 *
 * v1.4.0 (MSB 2016-12-16)
 * - Added handling of adding new Contracts to existing Lumenaza Customers
 *   (SOBCRM-763)
 *
 * @version 1.9.0 (2017-12-20)
 */
public class LumenazaContractTriggerHandler extends TriggerHandler {
    
    private final String sDebugHeader = 'LumenazaContractTriggerHandler.';

    public override void beforeUpdate() {
        this.sanitizeIbanNumber(); 
        this.setCustomerNumber();
        this.setBankDataFromRelatedBankData();
    }
    
    public override void beforeInsert() {
        this.sanitizeIbanNumber();
        this.setBankDataFromRelatedBankData();
    }

    /**
     * Sets bank data to Contract from related BankData record
     * if Contract.BankData__c has changed
     * If it was set to NULL concerning fields will be set to NULL
     *
     * @see GeneralTriggerTests.testBankDataChange()
     * @author Marko Schmalenbach <marko@die-interaktiven.de>
     * @since 2016-12-16
     */
    public void setBankDataFromRelatedBankData() {

        String sDebugHere = sDebugHeader + 'setBankDataFromRelatedBankData() - ';

        Set<Id> lsetBankDataIds = new Set<Id>();
        Map<String,String> mapMappingBankDataContractFields = BankDataTriggerHandler.mapMappingBankDataContractFields;

        Map<Id,Contract> mapContractOld = (Map<Id,Contract>)Trigger.oldMap;
        Set<Id> lsetContractsWithBankDataToReset = new Set<Id>();

        for (Contract oContract : (List<Contract>)Trigger.new) {

            // UPDATE
            if (Trigger.isUpdate) {

                Contract oContractOld = mapContractOld.get(oContract.Id);

                // If BankData relation was deleted
                if (oContractOld.BankData__c != NULL && oContract.BankData__c == NULL) {
                    System.debug(sDebugHere + 'BankData__c has changed to NULL for Contract ' + oContract.ContractNumber);
                    lsetContractsWithBankDataToReset.add(oContract.Id);
                }
                // Else if BankData is given and has changed
                else if (Contract.BankData__c != NULL && oContractOld.BankData__c != oContract.BankData__c) {
                    lsetBankDataIds.add(oContract.BankData__c);
                }
            }
            // INSERT
            else if (Trigger.isInsert && oContract.BankData__c != NULL) {
                lsetBankDataIds.add(oContract.BankData__c);
            }
        }

        Map<Id,BankData__c> mapBankData = new Map<Id,BankData__c>();

        // Set bank data from BankData__c
        if (!lsetBankDataIds.isEmpty()) {

            List<BankData__c> listBankDatas = (List<BankData__c>) Database.query('SELECT Id,' + String.join(new List<String>(mapMappingBankDataContractFields.keySet()), ',') + ' FROM BankData__c WHERE Id IN :lsetBankDataIds');

            for (BankData__c oBankData : listBankDatas) {
                mapBankData.put(oBankData.Id, oBankData);
            }
        }

        for (Contract oContract : (List<Contract>)Trigger.new) {

            BankData__c oBankData;

            if (oContract.BankData__c != NULL && mapBankData.get(oContract.BankData__c) != NULL) {
                oBankData = mapBankData.get(oContract.BankData__c);
            }

            for (String sBankDataField : mapMappingBankDataContractFields.keySet()) {

                String sContractField = mapMappingBankDataContractFields.get(sBankDataField);

                if (oBankData != NULL) {
                    oContract.put(sContractField, oBankData.get(sBankDataField));
                    System.debug(sDebugHere + '(' + (Trigger.isInsert ? 'INSERT' : (Trigger.isUpdate ? 'UPDATE' : 'Unknown trigger context')) + ') Set Contract field "' + sContractField + '" to "' + oBankData.get(sBankDataField) + '"');
                }
                else if (lsetContractsWithBankDataToReset.contains(oContract.Id)) {
                    oContract.put(sContractField, NULL);
                    System.debug(sDebugHere + '(UPDATE) Set Contract field "' + sContractField + '" to NULL');
                }
            }
        }
    }

    /**
     * After update of contract(s)
     *
     * If a contract is updated via API is managed
     * by LumenazaApi and LumenazaContract class.
     * According to them a sync is only trigger if
     * - the sync is activated in the LumenazaSettings__c with name "api" via ApiDoSync__c
     * - the Contract has Status "Activated" (which can only be set on updates!)
     * - the Contract's field LumenazaSkipApiCall__c is set to false
     * - the Contract's status before was "Draft" and is now "Activated" or is "Activated"
     *   and needs an update (see LumenazaContract.needsUpdate())
	 */
    public override void afterUpdate() {
        // Inactive due to SOBCRM-1123
        // this.saveVoucherCodeAsBonus();
        this.sendActivatedEnergyContractsToLumenaza();
    }
        
    /**
     * Save VoucherCode of Contract as Bonus__c
     * 
     * (only Community Contracts have one)
     *
     * ! Currently not in use due to SOBCRM-1123
     * 
     * Tested by class GeneralTriggerTests
     * 
     * @see https://interaktiv.jira.com/browse/SOBCRM-534
     * @author Marko Schmalenbach <marko@die-interaktiven.de>
     * @since 2016-08-05
     * @version 1.0.0 (2016-08-05)
     */
    public void saveVoucherCodeAsBonus() {
        
        Map<Id,Contract> mContractsOld = (Map<Id,Contract>) Trigger.oldMap;
        List<Contract> lContractWithBonus = new List<Contract>();
        
        // Collect Contracts which are activated and have a VoucherCode
		for (Contract oContract : (List<Contract>)Trigger.new) {
            
            // SOBCRM-803 - dino.ursic@die-interaktiven.de, 21.02.2017
            // Bonus should not be created for Type 'sonnenbatterieCity-DE'
            if (oContract.Type__c == 'sonnenbatterieCity-DE')
                continue;
            
            if (oContract.Status == 'Activated' && mContractsOld.get(oContract.Id).Status == 'Draft' && oContract.VoucherCode__c != NULL) {
                lContractWithBonus.add(oContract);
            }
        }        
        if (lContractWithBonus.isEmpty()) {
            return;
        }
        
        Campaign oCampaign;
        String sDebugHeaderHere = this.sDebugHeader + 'saveVoucherCodeAsBonus - ';
        
        List<Bonus__c> lNewBonuses = new List<Bonus__c>();
        List<CampaignMember> lNewCampaignMembers = new List<CampaignMember>();
        Set<Id> lsContactIdsForCampaignMembers = new Set<Id>();
        
        Id idCampaign = SonnenbatterieConstants.getCommunityContractBonusCampaignId();
        Id idBonusVoucherRecordType = SonnenbatterieConstants.getRecordTypeIdByObjectAndDeveloperName('Bonus__c', 'Voucher');
        
        System.debug(sDebugHeaderHere + 'Using CampaignId ' + idCampaign + ' and BonusVoucherRecordTypeId ' + idBonusVoucherRecordType);
        
        if (idCampaign == NULL) {
            return;
        }
        
        try {
        	oCampaign = [SELECT Id, BonusType__c, BonusUnit__c, BonusAmount__c FROM Campaign WHERE Id = :idCampaign];
        }
        catch(Exception e) {
        	System.debug(sDebugHeaderHere + 'Campaign not found');
            return;
        }
        
		for (Contract oContract : lContractWithBonus) { 
                            
            // For creating CampaignMembers
            if (oContract.CustomerSignedId != NULL) {
                lsContactIdsForCampaignMembers.add(oContract.CustomerSignedId);
            }
            
            lNewBonuses.add(new Bonus__c(
                RecordTypeId  = idBonusVoucherRecordType,
                BonusCode__c  = oContract.VoucherCode__c,
                Contract__c   = oContract.Id,
                CampaignId__c = oCampaign.Id,
                BonusType__c  = oCampaign.BonusType__c,
                Amount__c     = oCampaign.BonusAmount__c,
                Unit__c       = oCampaign.BonusUnit__c,
                StartDate__c  = System.today(),
                Active__c     = true
            ));            
        }   
        
        if (lNewBonuses.isEmpty()) {
	        System.debug(sDebugHeaderHere + 'No Bonuses created');
            return;
        }
        
        System.debug(sDebugHeaderHere + 'New Bonuses from VoucherCode: ' + lNewBonuses);            
        insert lNewBonuses;

        // Create CampaignMembers
        if (!lsContactIdsForCampaignMembers.isEmpty()) {
            
            // Check which Contacts are already members
            Set<Id> lsContactIdsWithMembership = new Set<Id>();
            
            for (CampaignMember oCampaignMember : [SELECT ContactId FROM CampaignMember WHERE CampaignId = :idCampaign AND ContactId IN :lsContactIdsForCampaignMembers]) {
            	lsContactIdsWithMembership.add(oCampaignMember.ContactId);    
            }
                
            for (Id idContact : lsContactIdsForCampaignMembers) {
                if (!lsContactIdsWithMembership.contains(idContact)) {
                    
                    lNewCampaignMembers.add(new CampaignMember(
                        ContactId = idContact,
                        Status = 'Bonus created',
                        CampaignId = idCampaign
                    ));	 
                    
                    // Don't forget to add this Membership just created - epic fail xD
                    lsContactIdsWithMembership.add(idContact);
                }
            } 
            
            if (!lNewCampaignMembers.isEmpty()) {
        		System.debug(sDebugHeaderHere + 'New CampaignMembers for Campaign ' + idCampaign + ': ' + lNewCampaignMembers);                            
                insert lNewCampaignMembers;
            }
            else {
        		System.debug(sDebugHeaderHere + 'No CampaignMembers created for Campaign ' + idCampaign);                                            
            }
        }
    }

    public void sendActivatedEnergyContractsToLumenaza() {

        Set<LumenazaObject> lumenazaContractsToUpsert = new Set<LumenazaObject>();
        
        // Get contracts before
        Map<Id,Contract> oldMap = (Map<Id,Contract>) Trigger.oldMap;

        Map<String,Id> mapRecordTypes = DiaUtilities.getRecordTypeMap(new List<String>{'Contract'}).get('Contract');

        Set<Id> lsetAccountIds = new Set<Id>();

        for (Contract contractAfter : (List<Contract>) Trigger.new) {

            // This can be evaluated because it's after trigger event!
            if (!contractAfter.IsValidForLumenazaSync__c) {
                continue;
            }
            
            // Instantiate a LumenazaContract by a Contract
            LumenazaContract lumenazaContract = new LumenazaContract(contractAfter);

            // Set old Contract on update
            if (Trigger.isUpdate) {
                Contract contractBefore = oldMap.get(contractAfter.id);                                
                lumenazaContract.setContractBefore(contractBefore);
            }                        
            // Add LumenazaContract to upsert list
            lumenazaContractsToUpsert.add(lumenazaContract);

            Id idAccount = contractAfter.AccountId;

            if (idAccount != NULL) {
                /*
                if (lsetAccountIds.contains(idAccount)) {
                    throw new LumenazaContractTriggerHandlerException(
                        'Cannot create more than one Lumenaza Contract for the same Account at the same time as the first ' +
                        'Contract has to wait for the customer ID at Lumenaza! Otherwise the second Contract' +
                        'would fail with an "saas_customer_id not unique" error.'
                    );
                }
                else {
                    lsetAccountIds.add(idAccount);
                }
                */
                lsetAccountIds.add(idAccount);
            }
        }

        // If any LumenazaContract validates to false everything is rolled
        // back otherwise Contracts will be upserted if API Sync is active       
        if (!lumenazaContractsToUpsert.isEmpty()) {

            Map<Id,List<String>> mapAccountIdToLumenazaCustomerId = LumenazaContract.checkOnMultipleContractsByAccountIds(lsetAccountIds);
            Set<Id> lsetAccountToInsertAContractFor = new Set<Id>();

            for (LumenazaObject lumenazaObject : lumenazaContractsToUpsert) {

                LumenazaContract lumenazaContract = (LumenazaContract)lumenazaObject;

                Id idAccount = lumenazaContract.getContract().AccountId;
                Integer iCountOfAccountLumenazaCustomerIds = mapAccountIdToLumenazaCustomerId.get(idAccount).size();

                if (iCountOfAccountLumenazaCustomerIds > 1) {
                    lumenazaContract.getContract().addError('Contract\'s Account has Contracts with multiple Lumenaza Customer IDs (' + String.join(mapAccountIdToLumenazaCustomerId.get(idAccount) , ', ') + ')!');
                }
                else if (iCountOfAccountLumenazaCustomerIds == 1) {

                    String sExistingLumenazaCustomerId = mapAccountIdToLumenazaCustomerId.get(idAccount).get(0);

                    // Set that this Contract's Account is an already existing
                    // Lumenaza Customer
                    lumenazaContract.setIsAccountLumenazaCustomer(TRUE, sExistingLumenazaCustomerId);
                }
                else {
                    // Contract's Account has no existing Lumenaza Contract
                    // and therefore no Lumenaza Customer ID
                    lumenazaContract.setIsAccountLumenazaCustomer(FALSE, NULL);
                }

                // Get upsert mode
                // (This MUST be called after setIsAccountLumenazaCustomer()! Otherwise
                // each Contract will query for itsself if their Account already is a
                // Lumenaza Customer!)
                String sUpsertMode = lumenazaContract.getUpsertMode();

                // Check if there are inserts of multiple Contracts for same Account
                // and raise an error if so
                if (sUpsertMode == 'insert' || sUpsertMode == 'insertForExistingCustomer') {
                    if (lsetAccountToInsertAContractFor.contains(idAccount)) {
                        lumenazaContract.getContract().addError(
                            'Cannot insert multiple Contracts for same Account at the same time! ' +
                            'This would raise an error at Lumenaza as this process is done asynchronously ' +
                            'and new Contracts for existing Customers have to be handled specially!'
                        );
                    }
                    else {
                        lsetAccountToInsertAContractFor.add(idAccount);
                    }
                }
            }

            // Try to init the Contract upsert and if any validation fails stop
            // the activation process by raising an validation error
            if (LumenazaApi.initUpsert(lumenazaContractsToUpsert) == FALSE) {

                for (LumenazaObject lumenazaObject : lumenazaContractsToUpsert) {

                    LumenazaContract lumenazaContract = (LumenazaContract)lumenazaObject;

                    if (lumenazaContract.hasError() == true) {
                        lumenazaContract.getContract().addError(lumenazaContract.getError());
                    }
                }
            }
        }
    }

    private void sanitizeIbanNumber() {
        // IBAN to uppercase and without invalid characters
        for (Contract contract : (List<Contract>) Trigger.new) {            
            if (contract.BankDataIBAN__c != NULL) {
                contract.BankDataIBAN__c = contract.BankDataIBAN__c.toUpperCase().replaceAll('[^A-Z0-9]', '');
            }
        }        
    }

    /**
     * Collects all Account IDs of the triggers Contracts
     * for setting their CustomerNoDatev__c (independent of
     * the Contract's acitvation status!)
     *
     * @see https://interaktiv.jira.com/browse/SOBCRM-912
     */
    private void setCustomerNumber() {
        
        List<Contract> listContracts = new List<Contract>();
        
        for (Contract oContract : (List<Contract>) Trigger.new) {
            listContracts.add(oContract);
        }
        
        setCustomerNumber(listContracts);
    }

    /**
     * Creates and set Account's CustomerNoDatev__c related
     * to the given Contracts
     */
    public void setCustomerNumber(List<Contract> contracts) {
        
        Set<Id> lsetAccounts = new Set<Id>();
        Integer iNextCustomerNo = AccountService.getNextDatevNumber();
        
        for (Contract oContract : contracts) {
            lsetAccounts.add(oContract.AccountId);
        }

        // Only set Datev No if not set yet
        Map<Id,Account> mapAccountsByIds = new Map<Id,Account>([
            SELECT  CustomerNoDatev__c 
            FROM    Account
            WHERE   Id IN: lsetAccounts 
            AND     CustomerNoDatev__c = NULL
            ORDER BY Id ASC
        ]);

        AccountService.updateAccountsCustomerDatevNumber(mapAccountsByIds.values(), iNextCustomerNo);

        // Set ContractingPartyDatevNo__c in Contract
        for (Contract oContract : (List<Contract>) Trigger.new) {
            if (mapAccountsByIds.containsKey(oContract.AccountId) ) {
                oContract.ContractingPartyDatevNo__c = mapAccountsByIds.get(oContract.AccountId).CustomerNoDatev__c;
            }
        }
    }
    
    public class LumenazaContractTriggerHandlerException extends Exception {}
}
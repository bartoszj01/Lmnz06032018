/**
 * LumenazaContractBatchTests
 *
 * Class for testing the Lumenaza Contract Changes mechanism
 *
 * Changelog
 * ---------
 *
 * v1.1.0 (2018-01-10)
 * - Added test for LumenazaContractDeliveryBatch (marko@die-interaktiven.de, SOBCRM-1025)
 *
 * v1.0.0 (2016-12-14)
 * - Initial
 *
 * @author  Marko Schmalenbach <marko@die-interaktiven.de>
 * @version 1.1.0 (2018-01-10)
 */
@IsTest
private class LumenazaContractBatchTests {

    private static final String DEBUG_HEADER = 'LumenazaContractBatchTests::';
    private static final String CRON_EXPRESSION = '0 0 0 15 3 ? 2022';
    
    private static final Integer CONTRACTS_TO_CREATE_COUNT = 25;
    private static final Integer CONTRACT_FIELDS_TO_CHANGE_COUNT = 5;

    private static final String INITIAL_FIRSTNAME = 'Voidy';
    private static final String INITIAL_LASTNAME = 'Bogusman';

    @testSetup
    static void setup() {

        String sDebugHere = DEBUG_HEADER + 'setup() - ';

        System.debug(sDebugHere + ' start');

        Map<String,Map<String,Id>> mapRecordTypeDeveloperNameToId = DiaUtilities.getRecordTypeMap(new List<String>{'Contract', 'Account'});

        Account oAccount = new Account(
            Name = 'ACME Co.',
            RecordTypeId = mapRecordTypeDeveloperNameToId.get('Account').get('BusinessAccount')
        );
        TriggerHandler.bypass('AccountTriggerHandler');
        insert oAccount;

        List<Contract> listContracts = new List<Contract>();

        // Energy Contract
        Contract oContract = new Contract(
            RecordTypeId                         = mapRecordTypeDeveloperNameToId.get('Contract').get('Energy'),
            AccountId                            = oAccount.Id,
            Status                               = 'Draft',
            ContractingPartyAccountName__c       = 'ACME Corp.',
            ContractingPartySalutation__c        = 'Herr',
            ContractingPartnerFirstname__c       = INITIAL_FIRSTNAME,
            ContractingPartnerLastname__c        = INITIAL_LASTNAME,
            ContractingPartyAcademicTitle__c     = 'Dr.',
            ContractingPartyEmail__c             = 'test@die-interaktiven.de',
            ContractingPartyPhone__c             = '007-123456',
            AnnualConsumption__c                 = '5000',
            BankDataFirstname__c                 = 'Voidy',
            BankDataLastname__c                  = 'Bogusman',
            BankDataIBAN__c                      = 'DE49733200730022666045',
            DeliveryStart__c                     = System.today().addMonths(1),
            BillingStreet__c                     = 'Voidstreet',
            BillingStreetNumber__c               = '4a',
            BillingPostalCode__c                 = '12345',
            BillingCity__c                       = 'Boguscity',
            MeterId__c                           = '7147192',
            PreviousProvider__c                  = '9904383000003',
            SEPADate__c                          = System.today(),
            ShippingStreet__c                    = 'Locusweg',
            ShippingStreetNumber__c              = '28',
            ShippingPostalCode__c                = '54321',
            ShippingCity__c                      = 'Shipcity',
            TariffType__c                        = 'household',
            Type__c                              = 'sonnenbatterieHome-DE',
            SubscriptionReason__c                = 'New Site (E02)',
            AmountOfFreeEnergy__c                = 5000,
            AnnualConsumptionTotal__c            = 10000,
            LumenazaContractId__c                = 'C16289616',
            LumenazaCustomerId__c                = 'DE16289616-1'
        );

        for (Integer i=1; i<=CONTRACTS_TO_CREATE_COUNT; i++) {
            Contract oNewContract = oContract.clone();
            oNewContract.LumenazaContractId__c += '-' + i;
            listContracts.add(oNewContract);
        }
        insert listContracts;

        for (Contract oContractToUpdate : listContracts) {
            oContractToUpdate.Status = 'Activated';
        }
        update listContracts;

        // Lumenaza Settings are needed
        LumenazaSettings__c settings = new LumenazaSettings__c(
            Name                 = LumenazaApi.settingsName,
            ApiDoSync__c         = true,
            ApiUseTest__c        = true,
            ApiTestUrl__c        = 'http://bogus.whitehouse.org',
            ApiTestUsername__c   = 'bogus',
            ApiTestPassword__c   = 'bogus',
            ApiTestAuthClient__c = 'bogus',
            ApiTestAuthSecret__c = 'bogus',
            ApiLiveUrl__c        = 'http://bogus.whitehouse.org',
            ApiLiveUsername__c   = 'bogus',
            ApiLivePassword__c   = 'bogus',
            ApiLiveAuthClient__c = 'bogus',
            ApiLiveAuthSecret__c = 'bogus'
        );
        insert settings;

        // Make some changes to create Changesets and Changes
        for (Contract oContractToUpdate : listContracts) {
            // Make CONTRACT_FIELDS_TO_CHANGE_COUNT changes
            oContractToUpdate.ContractingPartnerFirstname__c = 'Don';
            oContractToUpdate.ContractingPartnerLastname__c  = 'Schnulze';
            oContractToUpdate.BillingStreet__c               = 'Sesamstraße';
            oContractToUpdate.BillingPostalCode__c           = '54321';
            oContractToUpdate.BillingStreetNumber__c         = '1';
        }
        update listContracts;

        Integer iExpectedNumberOfChanges = CONTRACTS_TO_CREATE_COUNT * CONTRACT_FIELDS_TO_CHANGE_COUNT;

        List<LumenazaContractChange__c> listChanges = [SELECT Id FROM LumenazaContractChange__c WHERE Status__c = 'new'];
        System.assertEquals(iExpectedNumberOfChanges, listChanges.size(), 'Expect ' + iExpectedNumberOfChanges + ' changes with status "new"');

        System.debug(sDebugHere + Limits.getDmlStatements() + ' DMLs used, ' + (Limits.getLimitDmlStatements() - Limits.getDmlStatements()) + ' left');
        System.debug(sDebugHere + 'finished');

    }

    /**
     * Test fetching Contract info from Lumenaza
     *
     * @since 2018-01-10
     * @see LumenazaContractDeliveryBatch
     * @see https://interaktiv.jira.com/browse/SOBCRM-1025
     */
    @isTest
    static void testContractInformationBatch() {

        List<Contract> listContracts = [
            SELECT Id, Status, LumenazaCustomerId__c, LumenazaContractId__c, ConfirmedDeliveryStart__c, ConfirmedDeliveryEnd__c
            FROM Contract
        ];

        System.assert(listContracts.size() >= 2);

        Integer i = 0;

        for (Contract oContract : listContracts) {

            listContracts.get(i).LumenazaSkipApiCall__c = true;

            if (i == 0) {
                listContracts.get(i).Status = 'Activated';
                listContracts.get(i).ConfirmedDeliveryEnd__c = null;
                listContracts.get(i).ConfirmedDeliveryStart__c = null;
                listContracts.get(i).LumenazaContractId__c = 'C1000000';
                listContracts.get(i).LumenazaCustomerId__c = 'DE100000-1';
            }
            else if (i == 1) {
                listContracts.get(i).Status = 'Activated';
                listContracts.get(i).ConfirmedDeliveryStart__c = null;
                listContracts.get(i).ConfirmedDeliveryEnd__c = null;
                listContracts.get(i).LumenazaContractId__c = 'C2000000';
                listContracts.get(i).LumenazaCustomerId__c = 'DE200000-1';
            }
            else {
                listContracts.get(i).LumenazaContractId__c = null;
                listContracts.get(i).LumenazaCustomerId__c = null;
            }

            i++;
        }

        update listContracts;

        Test.startTest();

        // Schedule job (only for code coverage)
        System.schedule('Scheduled LumenazaContractDeliverySched', CRON_EXPRESSION, new LumenazaContractDeliverySched());

        String sDeliveryStart = '2017-01-01';
        String sDeliveryEnd   = '2018-12-31';

        // Only for coverage
        LumenazaContractDeliveryBatch oLumenazaContractDeliveryBatch = new LumenazaContractDeliveryBatch();
        oLumenazaContractDeliveryBatch.setTestApiMockResponse(
            new Map<String,Map<String,Object>>{
                listContracts.get(0).LumenazaContractId__c => new Map<String,Object>{
                    'response' => '{"delivery_end":"' + sDeliveryEnd + '","delivery_start":"' + sDeliveryStart + '"}',
                    'status'   => 200
                },
                listContracts.get(1).LumenazaContractId__c => new Map<String,Object>{
                    'response' => '',
                    'status'   => 200
                }
            });

        Database.executeBatch(oLumenazaContractDeliveryBatch);

        Test.stopTest();

        listContracts = [SELECT ConfirmedDeliveryStart__c, ConfirmedDeliveryEnd__c FROM Contract WHERE Id = :listContracts.get(0).Id OR Id = :listContracts.get(1).Id];

        System.assertEquals(sDeliveryStart, String.valueOf(listContracts.get(0).ConfirmedDeliveryStart__c));
        System.assertEquals(sDeliveryEnd, String.valueOf(listContracts.get(0).ConfirmedDeliveryEnd__c));

        // No change due to invalid JSON
        System.assertEquals(null, String.valueOf(listContracts.get(1).ConfirmedDeliveryStart__c));
        System.assertEquals(null, String.valueOf(listContracts.get(1).ConfirmedDeliveryEnd__c));

        // for coverage
        oLumenazaContractDeliveryBatch.setDebugLumenazaContractId('test');
        oLumenazaContractDeliveryBatch.setPersistence(false);
    }

    /**
     * Test if Lumenaza Contract Changes are created
     * and how they are processed by LumenazaContractChangeBatch
     * which triggers callouts on the changes endpoint of
     * Lumenaza via LumenazaContract > LumenazaApi
     */
    @isTest
    static void testContractChangeCreationBatch() {

        // Rechange two fields
        Contract oContractWithChangesToChange = [SELECT Id, ContractingPartnerFirstname__c, ContractingPartnerLastname__c FROM Contract LIMIT 1];

        oContractWithChangesToChange.ContractingPartnerFirstname__c = 'Foobar';
        oContractWithChangesToChange.ContractingPartnerLastname__c  = INITIAL_LASTNAME;

        update oContractWithChangesToChange;

        List<LumenazaContractChange__c> listContractChanges = new List<LumenazaContractChange__c>([
            SELECT Id, Name, Field__c, OldValue__c, NewValue__c
            FROM LumenazaContractChange__c
            WHERE Contract__c = :oContractWithChangesToChange.Id AND Field__c = 'last_name' AND NewValue__c = :INITIAL_LASTNAME
        ]);
        System.assertEquals(1, listContractChanges.size());

        Test.startTest();

        // Schedule job (only for code coverage)
        String jobId = System.schedule('Scheduled LumenazaContractChangeBatch', CRON_EXPRESSION, new LumenazaContractChangeBatch());

        // Execute LumenazaContractChangeBatch manually
        Id idBatchJob = Database.executeBatch(new LumenazaContractChangeBatch());

        Test.stopTest();

        // There should be pending changes now with a Lumenaza Change ID
        List<LumenazaContractChange__c> listHandledChanges = new List<LumenazaContractChange__c>([
            SELECT Id
            FROM LumenazaContractChange__c
            WHERE Status__c = 'pending' AND LumenazaChangeId__c != NULL
        ]);

        System.assert(listHandledChanges.size() > 0);
        System.assert(listHandledChanges.size() < Limits.getLimitCallouts(), 'Processed Changes count must be lower than callout limit');

        // Expect 3 cancelled Changes
        listHandledChanges = new List<LumenazaContractChange__c>([
            SELECT Id, StatusReason__c
            FROM LumenazaContractChange__c
            WHERE Status__c = 'cancelled'
        ]);

        System.assertEquals(3, listHandledChanges.size());

        // Change #1 is cancelled because it's overruled by a newer one (firstname = 'Foobar')
        // Changes #2 and #3 are cancelled because there would be no change from the oldest Change to
        // the latest for the concerning field value:
        //      (1) lastname was initially "Bogusman"
        //      (2) it was changed to "Schnulze" (makes one Change)
        //      (3) and rechanged back to "Bogusman"
        // The last two changes are dismissed/cancelled
    }

    /**
     * Tests the check of pending Lumeneaza Contract Changes for status
     * changes and updates them accordingly
     */
    @isTest
    static void testContractChangeQueryBatch() {

        String sChangeIdPrefix = 'changeId-';

        // Set a few Changes to "pending"
        List<LumenazaContractChange__c> listChanges = new List<LumenazaContractChange__c>([SELECT Id FROM LumenazaContractChange__c WHERE Status__c = 'new' LIMIT 5]);
        System.assertEquals(5, listChanges.size());

        Integer i = 1;
        for (LumenazaContractChange__c oChange : listChanges) {
            oChange.Status__c = 'pending';
            oChange.LumenazaChangeId__c = sChangeIdPrefix + (i++); // must be unique
        }
        // Bypass trigger
        TriggerHandler.bypass('LumenazaContractTriggerHandler');
        update listChanges;
        TriggerHandler.clearBypass('LumenazaContractTriggerHandler');

        // Simulate a check result with missing #5 Change
        LumenazaRestApiMockDispatcher.setResultBodyNextRoute(
            '[' +
                '{"change_id": "' + sChangeIdPrefix + '1", "status": "stored"},' +
                '{"change_id": "' + sChangeIdPrefix + '2", "status": "rejected"},' +
                '{"change_id": "' + sChangeIdPrefix + '3", "status": "pending"},' +
                '{"change_id": "' + sChangeIdPrefix + '4", "status": "bogus"}' +
            ']',
            200
        );

        Test.startTest();

        // Schedule job (only for code coverage)
        String jobId = System.schedule('Scheduled LumenazaContractChangeCheckBatch', CRON_EXPRESSION, new LumenazaContractChangeCheckBatch());

        // Execute it manually
        Id idBatchJob = Database.executeBatch(new LumenazaContractChangeCheckBatch());

        Test.stopTest();

        // Check results
        listChanges = new List<LumenazaContractChange__c>([SELECT Status__c, LumenazaChangeId__c FROM LumenazaContractChange__c WHERE Id IN :listChanges ORDER BY LumenazaChangeId__c ASC]);

        for (LumenazaContractChange__c oChange : listChanges) {
            if (oChange.LumenazaChangeId__c == sChangeIdPrefix + '1') {
                System.assertEquals('stored', oChange.Status__c);
            }
            else if (oChange.LumenazaChangeId__c == sChangeIdPrefix + '2') {
                System.assertEquals('rejected', oChange.Status__c);
            }
            else if (oChange.LumenazaChangeId__c == sChangeIdPrefix + '3') {
                System.assertEquals('pending', oChange.Status__c);
            }
            else if (oChange.LumenazaChangeId__c == sChangeIdPrefix + '4') {
                System.assertEquals('error', oChange.Status__c); // Invalid status "bogus"
            }
            else if (oChange.LumenazaChangeId__c == sChangeIdPrefix + '5') {
                System.assertEquals('error', oChange.Status__c); // Change ID not found
            }
        }
    }
}
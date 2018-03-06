/**
 * Lumenaza Contract object
 *
 * Changelog
 * ---------
 *
 * v1.11.0 (MSB 2017-11-09)
 * - needsUpsert(): Check if Contract is locked for an update to prevent redundant callouts
 *
 * v1.10.0 (MSB 2017-11-09)
 * - CONTRACT_STATUS_ACTIVATED is now set by Contract.LumenazaActivationStatus__c
 *   so that the status at which sync to Lumenaza is triggered can be set individually (SOBCRM-1093)
 *
 * v1.9.0 (MSB 2017-06-20)
 * - Added handling of "sonnenStrom" (SOBCRM-984)
 *
 * v1.8.0 (MSB 2017-03-23)
 * - Added validTariffTypes as configuration property and added tariff_type "sonnenCity"
 * - validate(): Added validation for "tariff_type" according to upserMode (SOBCRM-852)
 * - Fix: Raise of validation error was turned off accidentally in an older
 *   commit - urgh :/
 *
 * v1.7.2 (MSB 2017-01-02)
 * - Fix: Prevent sending of company_name if is_business is false
 *
 * v1.7.1 (MSB 2016-12-22)
 * - Fix: If the Contract should be revoked hasCustomUpsert() must respect that
 *   as this is no field change at all. This requires a special callout to
 *   revoke at Lumenaza.
 *
 * v1.7.0 (MSB 2016-12-15)
 * - Fix in initLumenazaFields(): Field "title" was renamed to "name_title"
 * - Lumenaza fields are now reduced to the relevant depending on the introduced
 *   "upsertMode" (update, insert, insertForExistingCustomer). By this irrelevant
 *   fields are not longer validated too.
 * - Added a lot to add new Contracts to existing Lumenaza Customers (SOBCRM-763)
 *   (New methods isAccountLumenazaCustomer(), checkOnMultipleContractsByAccountIds(),
 *   setIsAccountLumenazaCustomer(), ...)
 *
 * v1.6.0 (MSB 2016-12-14)
 * - Added handling of Lumenaza Contract Changes as changes cannot be done
 *   by simple updating the Contract via Lumenaza API (see customerUpsert())
 *   (SOBCRM-669)
 * - needsUpdate(): Extended debugging
 * - Added LumenazaContractException class
 *
 * v1.5.0 (MSB 2016-11-29)
 * - persist(): Added error handling for Case
 *
 * v1.4.0 (MSB 2016-11-15)
 * - Added "sonnenFlat" (tariff_type)
 *
 * v1.3.0 (MSB 2016-10-06)
 * - Implemented revokation of contract (SOBCRM-668)
 *
 * v1.2.0 (MSB 2016-10-05)
 * - Revised for using Lumenaza API v3 (SOBCRM-667)
 *
 * v1.1.0 (MSB 2016-06-03)
 * - Luemenaza field "previous_provider" is optional on "subscription_reason" E01 and E02 (SOBCRM-361)
 * - Removed "saas_contract_id" from lumenaza fields
 * - Added optional field "sepa_reference" for lumenaza fields (SOBCRM-378)
 * - Set lumenaza field "sepa_date"
 *
 * v1.0.0 (2016-01-27)
 * - Initial
 *
 * @see LumenazaTest
 * @author  Marko Schmalenbach <marko@die-interaktiven.de>
 * @version 1.10.0 (2017-11-09)
 */
public class LumenazaContract extends LumenazaObject {

    private static final String DEBUG_HEADER = 'LumenazaContract';

    private static String CONTRACT_STATUS_REVOKE    = 'Revoked';
    private static String CONTRACT_STATUS_DRAFT     = 'Draft';
    private static String CONTRACT_STATUS_ACTIVATED = 'Activated';

    private Contract contract;

    private Contract contractBefore;

    private String lumenazaCustomerId;
    private String lumenazaCustomerIdOfExistingContract;

    private String lumenazaContractId;

    private String specialAction;

    private Boolean isLumenazaCustomer;

    private static Map<String,List<Map<String,List<SObject>>>> mapObjectsForCustomUpsert = new Map<String,List<Map<String,List<SObject>>>>();

    private Map<String,Set<String>> validFieldsPerUpsertMode;

    public static final Set<String> validTariffTypes = new Set<String>{
        'household',
        'heatpump',
        'sonnenFlat',
        'sonnenCity',
        'sonnenStrom' // since 2017-06-14, SOBCRM-984
    };

    /**
     * Init LumenazaFields
     */
    protected override void initLumenazaFields() {

        this.lumenazaFields = new Map<String,String>{
            'is_business'                     => NULL, // (mandatory)
            'company_name'                    => NULL, // (mandatory for companies)
            'salutation'                      => NULL, // (mandatory) „Herr“ or „Frau“
            //'titel'                         => NULL, // (deprecated since API v3)
            'name_title'                      => NULL, // (optional, „Dr.“, „Prof.“, „Prof. Dr.“ , since API v3) !Changed to name_title by v1.7.0
            'first_name'                      => NULL, // (of contact for companies) (mandatory)
            'last_name'                       => NULL, // (of contact for companies) (mandatory)
            'birthday'                        => NULL, // (optional) format: YYYY-MM-DD, since API v3)
            'telephone'                       => NULL, // (optional)
            'email'                           => NULL, // (mandatory)
            'deliv_address_street'            => NULL, // (mandatory)
            'deliv_address_house_number'      => NULL, // (mandatory)
            'deliv_address_zipcode'           => NULL, // (mandatory),
            'deliv_address_city'              => NULL, // (mandatory),
            'deliv_address_addition'          => NULL, // (optional, additions to the delivery address, since API v3, NOT IN USE),
            //'delivery_start'                => NULL, // (deprecated since API v3)
            'preferred_delivery_start'        => NULL, // (optional, format: YYYY-MM-DD, the preferred delivery start if requested by the customer. This date has to lie two weeks in the future if the subscription_reason is "E03" and up to six weeks in the past if the reason is "E01" or "E02", since API v3)
            'bill_address_street'             => NULL, // (if empty we assume the delivery address data),
            'bill_address_house_number'       => NULL, // (if empty we assume the delivery address data),
            'bill_address_zipcode'            => NULL, // (if empty we assume the delivery address data),
            'bill_address_city'               => NULL, // (if empty we assume the delivery address data),
            'bill_address_addition'           => NULL, // (optional, since API v3, NOT IN USE)
            'subscription_reason'             => NULL, // (mandatory) Move into Location (E01) | New Site (E02) | Change of Provider (E03)
            'meter_id'                        => NULL, // (mandatory) the ID for the meter
            'meteringpoint_id'                => NULL, // (optional), the meteringpoint (Zählpunkt)
            'previous_provider'               => NULL, // (mandatory, optional on subscription_reason E01 and E02) this should be already the Marketpartner ID of the „Alt-Lieferant". IDs are managed by BDEW (https://bdew-codes.de/Codenumbers/BDEWCodes/CodeOverview)
            'annual_consumption'              => NULL, // (mandatory), the yearly consumption as indicated on the latest year end bill of the customer.
            'bank_data_first_name'            => NULL, // (mandatory), owner of the account
            'bank_data_last_name'             => NULL, // (mandatory), owner of the account
            'bank_data_iban'                  => NULL, // (mandatory),
            'sepa_date'                       => NULL, // (mandatory, format: YYYY-MM-DD), the dated where the sepa reference form has been signed by the customer or the date of the online contract.
            'sepa_reference'                  => NULL, // (optional) SEPA reference
            'tariff_type'                     => NULL, // (mandatory), see property "validTariffTypes"
            'saas_customer_id'                => NULL, // In case the consumer_id is created by the REST API client, this field is used to communicate this information. Note: requires project specific adaptation
            'free_amount'                     => NULL, // (optional, integer, since API v3), in case of using a flat tariff this is the free amount (in kWh) for the first step
            // Salesforce field consumption_before_battery_inst is resolved to the longer Lumenaza name
            'consumption_before_battery_inst' => 'consumption_before_battery_installation' // (optional, integer, since API v3) in case of using a flat tariff this is the overall consumption (in kWh) before sign the contract
        };

        this.validFieldsPerUpsertMode = new Map<String,Set<String>>{

            // On creation of a new Lumenaza Contract
            'insert' => new Set<String>{
                'is_business',
                'company_name',
                'salutation',
                'name_title',
                'first_name',
                'last_name',
                'birthday',
                'telephone',
                'email',
                'bill_address_street',
                'bill_address_house_number',
                'bill_address_zipcode',
                'bill_address_city',
                'bill_address_addition',
                'bank_data_first_name',
                'bank_data_last_name',
                'bank_data_iban',
                'sepa_date',
                'sepa_reference',

                'annual_consumption',
                'deliv_address_street',
                'deliv_address_house_number',
                'deliv_address_zipcode',
                'deliv_address_city',
                'deliv_address_addition',
                'meter_id',
                'meteringpoint_id',
                'preferred_delivery_start',
                'previous_provider',
                'subscription_reason',
                'tariff_type',
                'saas_customer_id',
                'free_amount',
                'consumption_before_battery_installation'
            },

            // This fields CANNOT BE MODIFIED according to API v3:
            //  - subscription_reason,
            //  - meteringpoint_id
            //  - tariff_type
            //  - saas_customer_id
            //  - free_amount
            //  - consumption_before_battery_installation
            'update' => new Set<String>{
                'is_business',
                'company_name',
                'salutation',
                'name_title',
                'first_name',
                'last_name',
                'birthday',
                'telephone',
                'email',
                'bill_address_street',
                'bill_address_house_number',
                'bill_address_zipcode',
                'bill_address_city',
                'bill_address_addition',
                'bank_data_first_name',
                'bank_data_last_name',
                'bank_data_iban',
                'sepa_date',
                'sepa_reference',

                'annual_consumption',
                'deliv_address_city',
                'deliv_address_house_number',
                'deliv_address_street',
                'deliv_address_zipcode',
                'deliv_address_addition',
                'preferred_delivery_start',
                'previous_provider',
                'meter_id'
            },

            // On creation of a new Lumenaza Contract which should be
            // added to an existing customer
            'insertForExistingCustomer' => new Set<String>{
                'annual_consumption',
                'deliv_address_city',
                'deliv_address_house_number',
                'deliv_address_street',
                'deliv_address_zipcode',
                'deliv_address_addition',
                'preferred_delivery_start',
                'previous_provider',
                'subscription_reason',
                'tariff_type',
                'meter_id',
                'meteringpoint_id',
                'free_amount',
                'consumption_before_battery_installation'
            }
        };
    }

    /**
     * Instantiate LumenazaContract by contract
     */
    public LumenazaContract(Contract contract) {

        if (contract == NULL) {
            throw new LumenazaContractException('Contract is null');
        }
        if (contract.Id == NULL) {
            throw new LumenazaContractException('Only existing contracts with ID can be passed');
        }
        this.initLumenazaFields();

        // Init by contract
        this.contract = contract;

        this.sObjectId = this.contract.Id;

        this.lumenazaCustomerId = this.contract.LumenazaCustomerId__c;
        this.lumenazaContractId = this.contract.LumenazaContractId__c;

        System.debug('LumenazaContract - Constructor: ' + contract);

        // Set contract's individual activation status (SOBCRM-1093)
        if (this.contract.LumenazaActivationStatus__c != NULL) {
            CONTRACT_STATUS_ACTIVATED = this.contract.LumenazaActivationStatus__c;
        }

        // Contract is to revoke
        // (As this constructor is also called by futureUpsert()
        // it requires that needsUpdate() is call by the API before.
        // So a revoked Contract isn't revoked twice ...)
        if (this.contract.Status == CONTRACT_STATUS_REVOKE) {
            this.specialAction = 'revoke';
        }

        this.setLumenazaFieldsFromObject(contract);
    }

    /**
     * Return Lumenaza fields with values
     *
     * This filters all fields according to what is configured
     * for the current upsert mode
     *
     * @see getUpsertMode()
     */
    public override Map<String,String> getLumenazaFields() {

        String sDebugHere = DEBUG_HEADER + '.getLumenazaFields() - ';

        System.debug(sDebugHere + 'Filter fields for upsert mode "' + this.getUpsertMode() + '"');

        // MUST respect upsertMode!
        String sUpsertMode = this.getUpsertMode(); // insert, update, insertForExistingCustomer
        Set<String> lsetValidFieldsForMode = this.validFieldsPerUpsertMode.get(sUpsertMode);

        Map<String,String> mapLumenazaFields = super.getLumenazaFields().clone();

        for (String sFieldName : mapLumenazaFields.keySet()) {
            if (!lsetValidFieldsForMode.contains(sFieldName)) {
                mapLumenazaFields.remove(sFieldName);
            }
        }

        // To avoid Lumenaza error on unneccessary fields
        if (mapLumenazaFields.get('is_business') == 'false') {
            mapLumenazaFields.remove('company_name');
        }

        return mapLumenazaFields;
    }

    /**
     * Returns upsert mode
     */
    public String getUpsertMode() {

        String sMode = 'insert';

        // If Contract has a Lumenaza Contract ID
        if (this.getLumenazaContractId() != NULL) {
            sMode = 'update';
        }
        // If
        // - Contract has NO Lumenaza Contract ID AND
        // - Customer already exists at Lumenaza
        else if (this.isAccountLumenazaCustomer()) {
            sMode = 'insertForExistingCustomer';
        }

        return sMode;
    }

    /**
     * Init by contract ID
     */
    public LumenazaContract(Id contractId) {
        this((Contract)Database.query('SELECT ' + DiaUtilities.returnAllFieldsAsString('Contract') + ' FROM Contract WHERE Id = :contractId'));
    }

    /**
     * Init future upsert
     */
    public override void initFutureUpsert() {
        if (Test.isRunningTest() == true) {
            new LumenazaContract(this.sObjectId).persist();
        }
        else {
            LumenazaContract.futureUpsert(this.sObjectId);
        }
    }

    /**
     * Future upsert of a LumenazaContract by a contract ID
     */
    @future(callout=true)
    public static void futureUpsert(Id contractId) {
        System.debug('LumenazaContract - futureUpsert() with contract ' + contractId);
        new LumenazaContract(contractId).persist();
    }

    /**
     * Returns if class has own upsert handling
     *
     * If Contract has Lumenaza Customer ID and there is
     * no revokation to do then there must be a change
     * in the Contract's data
     */
    public override Boolean hasCustomUpsert() {

        // Return TRUE on update but not on revokation!
        Boolean bChangedToRevoke = (
            this.contractBefore != NULL &&
                this.contract != NULL &&
                this.contractBefore.Status == CONTRACT_STATUS_ACTIVATED &&
                this.contract.Status == CONTRACT_STATUS_REVOKE
        );

        // If there is a Lumenza Customer Id the Contract must be activated
        // and synchronized to Lumenaza in the past
        return (this.getLumenazaCustomerId() != NULL && !bChangedToRevoke) ? TRUE : FALSE;
    }

    /**
     * Do custom upsert
     *
     * This covers only updates with a Changeset mechanism.
     * As changes to an existing Contract cannot be made by simple
     * updating the Contract via Lumenaza API we create Changesets
     * with Changes which are asynchronously processed by a batch
     * later.
     *
     * @see hasCustomUpsert()
     */
    public override Boolean customUpsert() {

        String debugHere = DEBUG_HEADER + '.customUpsert() - ';

        // Only Updates are handled
        String customerId = this.getLumenazaCustomerId();
        String contractId = this.getLumenazaContractId();

        if (customerId == NULL) {
            throw new LumenazaContractException('Only updates are handled! Call hasCustomUpsert() first.');
        }
        if (contractId == NULL) {
            throw new LumenazaContractException('Missing Lumenaza Contract ID for update');
        }

        Integer errors = 0;

        if (this.needsUpdate() == TRUE) {
            if (this.validate() == FALSE) {
                errors++;
            }
        }
        else {
            System.debug(debugHere + 'Contract with ID "' + this.sObjectId + '" needs no update');
            return TRUE;
        }

        if (errors > 0) {
            return FALSE;
        }

        Map<String,Map<String,String>> mapUpdateFields = this.getUpdateFields();

        System.debug(debugHere + 'Fields with changes: ' + mapUpdateFields);

        if (mapUpdateFields.isEmpty()) {
            throw new LumenazaContractException('needsUpdate() returns true but no update fields are set');
        }

        //-------------------------------------------------
        // Register Changsets and Chaonges for insert
        //-------------------------------------------------
        Map<String,List<SObject>> mapForUpsert = new Map<String,List<SObject>>();

        // Create changeset
        LumenazaContractChangeset__c oChangeset = new LumenazaContractChangeset__c(
            Contract__c = this.sObjectId
        );
        mapForUpsert.put(String.valueOf(LumenazaContractChangeset__c.class), new List<SObject>{oChangeset});

        System.debug(debugHere + 'Created Lumenaza Contract Changeset: ' + oChangeset);

        // Add changes to changeset
        List<SObject> listChangesToInsert = new List<SObject>();

        for (String field : mapUpdateFields.keySet()) {

            Map<String,String> mapOldNewValue = mapUpdateFields.get(field);

            listChangesToInsert.add(new LumenazaContractChange__c(
                Contract__c = this.sObjectId,
                Field__c    = field,
                OldValue__c = mapOldNewValue.get('old'),
                NewValue__c = mapOldNewValue.get('new')
            ));
        }
        mapForUpsert.put(String.valueOf(LumenazaContractChange__c.class), listChangesToInsert);

        System.debug(debugHere + 'Created Lumenaza Contract Changes: ' + listChangesToInsert);

        // Add objects to upsert
        this.addObjectsForUpsert('changesToChangeset', mapForUpsert);

        return TRUE;
    }

    /**
     *  Adds an object for an upsert to a list to minimize DMLs
     *
     *  @see processObjectsForUpsert()
     */
    private void addObjectsForUpsert(String upsertType, Map<String,List<SObject>> objectsForUpsert) {

        if (mapObjectsForCustomUpsert == NULL) {
            mapObjectsForCustomUpsert = new Map<String,List<Map<String,List<SObject>>>>();
        }
        if (mapObjectsForCustomUpsert.get(upsertType) == NULL) {
            mapObjectsForCustomUpsert.put(upsertType, new List<Map<String,List<SObject>>>());
        }
        mapObjectsForCustomUpsert.get(upsertType).add(objectsForUpsert);
    }

    /**
     * Process objects for upsert
     *
     * @see customUpsert()
     */
    public override Boolean processObjectsForUpsert() {

        String sDebugHere = DEBUG_HEADER + '.processObjectsForUpsert() - ';

        if (!mapObjectsForCustomUpsert.isEmpty()) {

            for (String upsertType : mapObjectsForCustomUpsert.keySet()) {

                List<Map<String,List<SObject>>> listMapTypeToObjects = mapObjectsForCustomUpsert.get(upsertType);

                // Insert changeset and changes
                if (upsertType == 'changesToChangeset') {

                    // Bypass LumenazaContractTriggerHandler which would be triggered again
                    // because LumenazaContractChangeset__c is the detail part of the
                    // master/detail relationship with Contract!
                    TriggerHandler.bypass('LumenazaContractTriggerHandler');

                    try {

                        List<LumenazaContractChangeset__c> listAllChangesets = new List<LumenazaContractChangeset__c>();
                        List<List<LumenazaContractChange__c>> listAllChangesToChangeset = new List<List<LumenazaContractChange__c>>();

                        // Iterate of all Changsets with Changes maps and collect changesets and changes
                        for (Map<String, List<SObject>> mapTypeToObjects : listMapTypeToObjects) {

                            String sClassNameChangeset = String.valueOf(LumenazaContractChangeset__c.class);
                            String sClassNameChange = String.valueOf(LumenazaContractChange__c.class);

                            List<LumenazaContractChangeset__c> listChangesets = mapTypeToObjects.get(sClassNameChangeset);
                            List<LumenazaContractChange__c> listChanges = mapTypeToObjects.get(sClassNameChange);

                            if (listChangesets == NULL || listChangesets.isEmpty()) {
                                throw new LumenazaContractException('No ' + sClassNameChangeset + ' found to insert');
                            }
                            if (listChangesets.size() > 1) {
                                throw new LumenazaContractException('Only one ' + sClassNameChangeset + ' expected');
                            }
                            if (listChanges == NULL || listChanges.isEmpty()) {
                                throw new LumenazaContractException('No ' + sClassNameChange + ' found to insert');
                            }

                            listAllChangesets.add(listChangesets.get(0));
                            listAllChangesToChangeset.add(listChanges);
                        }

                        System.debug(sDebugHere + 'Insert ' + listAllChangesets.size() + ' changeset(s)');
                        // Insert all changesets
                        insert listAllChangesets;

                        Integer iChangesetIndex = 0 ;
                        List<LumenazaContractChange__c> listChangesToInsert = new List<LumenazaContractChange__c>();

                        for (List<LumenazaContractChange__c> listChangesToSetChangesetIdFor : listAllChangesToChangeset) {

                            Id idChangeset = listAllChangesets.get(iChangesetIndex).Id;

                            for (LumenazaContractChange__c oChange : listChangesToSetChangesetIdFor) {
                                oChange.LumenazaContractChangeset__c = idChangeset;
                                listChangesToInsert.add(oChange);
                            }
                            iChangesetIndex++;
                        }

                        System.debug(sDebugHere + 'Insert ' + listChangesToInsert.size() + ' change(s)');
                        insert listChangesToInsert;
                    }
                    finally {
                        // Restore LumenazaContractTriggerHandler
                        TriggerHandler.clearBypass('LumenazaContractTriggerHandler');

                        // IMPORTANT: Finally clear all handled objects!
                        // Otherwise they might be handled ony again because mapObjectsForCustomUpsert
                        // is a static member.
                        mapObjectsForCustomUpsert.get(upsertType).clear();
                    }

                }
                else {
                    throw new LumenazaContractException('Unkown upsertType "' + upsertType + '"');
                }
            }
        }

        return TRUE;
    }

    /**
     * Persist this object
     *
     * @return Boolean Success
     */
    public override Boolean persist() {

        // Validate and if false write to contract
        if (this.validate() == false) {
            return false;
        }

        Contract contract = this.contract;

        // Set Request time
        contract.Lumenaza_ApiRequestTime__c = System.now();

        String error = '';
        String errorDescription = '';

        // Upsert contract via API
        try {

            LumenazaApi api = new LumenazaApi();
            LumenazaApi.LumenazaApiResponse lumenazaResponse = api.upsertContract(this);

            System.debug('LumenazaContract - Got Lumenaza API Response: ' + lumenazaResponse);

            // Set request info
            contract.Lumenaza_ApiRequest__c = lumenazaResponse.requestInfo;

            if (lumenazaResponse.success == false) {
                contract.Lumenaza_ApiResponse__c = lumenazaResponse.error;
                error = lumenazaResponse.error;
            }
            else {

                contract.Lumenaza_ApiResponse__c = lumenazaResponse.response.getBody();

                if (lumenazaResponse.resultMap != NULL) {

                    Map<String,String> resultMap = lumenazaResponse.resultMap;

                    if (resultMap.containsKey('contract_id')) {
                        contract.LumenazaContractId__c = resultMap.get('contract_id');
                    }
                    if (resultMap.containsKey('consumer_id')) {
                        contract.LumenazaCustomerId__c = resultMap.get('consumer_id');
                    }
                }
            }

            if (lumenazaResponse.response != NULL) {

                if (Test.isRunningTest() && contract.Lumenaza_ApiStatusCode__c == 'TEST') {
                    System.debug('LumenazaContract - Set a fake error to raise a case');
                    error = 'TESTERROR';
                }

                contract.Lumenaza_ApiStatusCode__c = String.valueOf(lumenazaResponse.response.getStatusCode());
            }
            else {
                // Error on NULL response
                System.debug('LumenazaContract - lumenazaResponse.response is NULL');
                error = 'The lumenazaResponse.response was NULL so the response could not be written to the Contract';
                contract.Lumenaza_ApiResponse__c = error;
                errorDescription = '\n\nLumenazaResponse: ' + lumenazaResponse;
            }
        }
        catch (Exception e) {
            contract.Lumenaza_ApiResponse__c = e.getMessage();
            error = e.getMessage() + ' ' + e.getStackTraceString();
        }

        try {
            TriggerHandler.bypass('LumenazaContractTriggerHandler');
            System.debug('LumenazaContract - Update contract with bypassing LumenazaContractTriggerHandler: ' + contract);
            update contract;
            TriggerHandler.clearBypass('LumenazaContractTriggerHandler');
        }
        catch (Exception e) {
            error = e.getMessage() + ' ' + e.getStackTraceString();
        }

        // Open case on error
        if (error.length() > 0) {

            // Tested by LuemenazaTest.testLumenazaContractCreationWithErrorAndCase()
            Case errorCase = this.prepareErrorCase();

            errorCase.Contract__c = contract.Id;
            errorCase.AccountId = contract.AccountId;
            errorCase.ContactId = contract.CustomerSignedId;

            errorCase.subject = 'Error at Lumenaza Sync for Contract';
            errorCase.description  = 'Error: ' + error + '\n\n';
            errorCase.description += errorDescription;

            // Set Subcategory__c
            // E01, Falscher Kunden/Firmenname
            // E02, Falsche Liefer-/Rechnungsadresse
            // E03, Falsche Zählernummer
            // E04, Falscher Altlieferant
            // E05, Falsches Netzgebiet
            // E06, Falscher Wechselgrund
            // E07, Falsches Lieferdatum
            // E08, Falsche Kontodaten
            // E09, Unplausibler Jahresverbrauch
            // E10, Unplausible Dateninhalte
            // E11, Lieferstelle nicht bekannt
            // E12, Fehler in Zähler-Kunden-Zuordnung
            // E13, Sonstiges

            if (error.containsIgnoreCase('company_name')) {
                errorCase.Subcategory__c = 'E01, Falscher Kunden/Firmenname';
            }
            else if (error.containsIgnoreCase('Zipcode not found in database')) {
                errorCase.Subcategory__c = 'E02, Falsche Liefer-/Rechnungsadresse';
            }
            else if (error.containsIgnoreCase('previous provider not set') || error.containsIgnoreCase('market partner ID not found')) {
                errorCase.Subcategory__c = 'E04, Falscher Altlieferant';
            }
            else if (error.containsIgnoreCase('delivery start has to be two weeks in future')) {
                errorCase.Subcategory__c = 'E07, Falsches Lieferdatum';
            }
            else if (error.containsIgnoreCase('bank_data_first_name') || error.containsIgnoreCase('bank_data_iban')) {
                errorCase.Subcategory__c = 'E08, Falsche Kontodaten';
            }
            else if (error.containsIgnoreCase('wrong date format')
                || error.containsIgnoreCase('not unique')
                || error.containsIgnoreCase('this field is required if tariff equals to sonnenflat')
                ) {
                errorCase.Subcategory__c = 'E10, Unplausible Dateninhalte';
            }

            insert errorCase;
        }

        return true;
    }

    /**
     * Set the contract before to check if the
     * object has to be updated
     */
    public void setContractBefore(Contract contractBefore) {
        this.contractBefore = contractBefore;
    }

    public Contract getContract() {
        return this.contract;
    }

    public override Boolean needsUpdate() {

        String debugHere = DEBUG_HEADER + '.needsUpdate(): ';

        Boolean needsUpdate = false;

        // Updates are currently not possible!
        // (See https://interaktiv.jira.com/browse/SOBCRM-667)
        // if (this.lumenazaCustomerId != NULL) {
        //     System.debug('LumenazaContract - needsUpdate(): Updates are currently NOT allowed due to changes at the API v3 (see SOBCRM-667)');
        //     return false;
        // }

        if (this.isLocked('upsert')) {
            System.debug(debugHere + 'Contract is already registered for an update: skip!');
            return false;
        }
        if (this.contract.LumenazaSkipApiCall__c == true) {
            System.debug(debugHere + 'LumenazaSkipApiCall__c is active: no update');
            return false;
        }
        if (this.contract.Status != CONTRACT_STATUS_ACTIVATED && this.contract.Status != CONTRACT_STATUS_REVOKE) {
            System.debug(debugHere + 'Contract ' + this.contract.Id + ' status is not ' + CONTRACT_STATUS_ACTIVATED + ' nor ' + CONTRACT_STATUS_REVOKE + ' (' + this.contract.Status + '): no update');
            return false;
        }

        if (this.contractBefore != NULL) {

            // No update if status is still revoked
            if (this.contractBefore.Status == CONTRACT_STATUS_REVOKE && this.contract.Status == CONTRACT_STATUS_REVOKE) {
                System.debug(debugHere + 'Contract ' + this.contract.Id + ' status is "' + CONTRACT_STATUS_REVOKE + '" and has not changed: no update');
                return false;
            }

            // If Contract has no Lumenaza Customer ID and no Lumenaza Contract ID then
            // update will be forced as insert (API checks on existing ID to destinguish
            // between INSERT and UPDATE)
            if (this.contract.Status == CONTRACT_STATUS_ACTIVATED && this.getLumenazaContractId() == NULL && this.getLumenazaCustomerId() == NULL) {
                System.debug(debugHere + 'Contract ' + this.contract.Id + ' is ' + CONTRACT_STATUS_ACTIVATED + ' and has no Lumenaza Customer and Contract ID, force creation at Lumenaza!');
                return true;
            }

            // Change to ACTIVATED
            if (this.contractBefore.Status != CONTRACT_STATUS_ACTIVATED && this.contract.Status == CONTRACT_STATUS_ACTIVATED) {

                // If contract was synched before
                if (this.getLumenazaContractId() != NULL || this.getLumenazaCustomerId() != NULL) {
                    //throw new LumenazaContractException('Cannot activate Contract with given Lumenaza Conract or Customer ID');
                    System.debug(debugHere + 'Cannot activate Contract with given Lumenaza Conract or Customer ID');
                    return false;
                }
                else {
                    System.debug(debugHere + 'Contract ' + this.contract.Id + ' is now ' + CONTRACT_STATUS_ACTIVATED + ', force creation at Lumenaza!');
                    return true;
                }
            }

            // ACTIVATED -> REVOKE
            if (this.contractBefore.Status == CONTRACT_STATUS_ACTIVATED && this.contract.Status == CONTRACT_STATUS_REVOKE) {

                System.debug(debugHere + 'Contract ' + this.contract.Id + ' should be revoked');

                if (this.lumenazaContractId == NULL) {
                    System.debug(debugHere + 'Missing Lumenaza Contract ID: no update');
                    return false;
                }
                if (this.lumenazaCustomerId == NULL) {
                    System.debug(debugHere + 'Missing Lumenaza Customer ID: no update');
                    return false;
                }

                return true;
            }

            System.debug(debugHere + 'Status was "' + this.contractBefore.Status + '" before and now is "' + this.contract.Status + '", check all relevant fields for update');

            System.debug(debugHere + 'Get old values by creating a fake LumenazaContract object');
            LumenazaContract lumenazaContractOld = new LumenazaContract(this.contractBefore);

            Map<String,String> mapOld = lumenazaContractOld.getLumenazaFields();
            Map<String,String> mapNew = this.getLumenazaFields();

            // Clear update fields
            this.updateFields = new Map<String,Map<String,String>>();

            for (String fieldName : mapNew.keySet()) {

                String valueNew = mapNew.get(fieldName);
                String valueOld = mapOld.get(fieldName);

                System.debug(debugHere + 'Compare "' + fieldName + '" before "' + valueOld + '", now "' + valueNew + '"');

                if (valueNew != valueOld) {

                    this.updateFields.put(fieldName, new Map<String,String>{
                        'old' => valueOld,
                        'new' => valueNew
                    });

                    System.debug(debugHere + 'Field "' + fieldName + '" -> old "' + valueOld + '"" <> new "' + valueNew + '"');
                    needsUpdate = true;
                }
            }
        }

        System.debug(debugHere + 'Needs update: ' + (needsUpdate ? 'yes' : 'no'));
        return needsUpdate;
    }

    /**
     * Validates the object
     */
    public override Boolean validate() {

        String sDebugHere = DEBUG_HEADER + '.validate() - ';

        // This returns only the fields which can be used for
        // the given upsertMode!
        Map<String,String> mapLumenazaFields = this.getLumenazaFields();

        while (TRUE) {

            if (this.specialAction == 'revoke') {
                if (this.contract.Status != CONTRACT_STATUS_REVOKE) {
                    this.setError('Status must be "' + CONTRACT_STATUS_REVOKE + '" for Revokation of Contract');
                    break;
                }
                if (this.lumenazaContractId == NULL) {
                    this.setError('Contract has no Lumenaza Contract ID');
                    break;
                }
                if (this.lumenazaCustomerId == NULL) {
                    this.setError('Contract has no Lumenaza Customer ID');
                    break;
                }
                break;
            }

            System.debug(sDebugHere + 'Fields to validate: ' + mapLumenazaFields);

            // Check if any changes which were done in the past failed and are not resolved
            Decimal dFailedChanges = this.contract.ChangesFailedCount__c;

            if (dFailedChanges > 0) {
                this.setError('Contract has ' + dFailedChanges + ' unresolved failed change' + (dFailedChanges > 1 ? 's' : '') + '. Please resolve them before making any new changes!');
                break;
            }

            for (String fieldName : mapLumenazaFields.keySet()) {

                String value = (mapLumenazaFields.get(fieldName) == NULL) ? '' : mapLumenazaFields.get(fieldName).trim();

                if (
                    (
                        fieldName == 'is_business' ||
                            fieldName == 'salutation' ||
                            fieldName == 'first_name' ||
                            fieldName == 'last_name' ||
                            fieldName == 'email' ||
                            fieldName == 'deliv_address_street' ||
                            fieldName == 'deliv_address_house_no' ||
                            fieldName == 'deliv_address_zipcode' ||
                            fieldName == 'deliv_address_city' ||
                            fieldName == 'bill_address_street' ||
                            fieldName == 'bill_address_house_no' ||
                            fieldName == 'bill_address_zipcode' ||
                            fieldName == 'bill_address_city' ||
                            fieldName == 'subscription_reason' ||
                            fieldName == 'meter_id' ||
                            fieldName == 'annual_consumption' ||
                            fieldName == 'bank_data_first_name' ||
                            fieldName == 'bank_data_last_name' ||
                            fieldName == 'bank_data_iban' ||
                            fieldName == 'sepa_date' ||
                            (mapLumenazaFields.get('is_business') == 'true' && fieldName == 'company_name')
                    ) && value.length() == 0) {
                    this.setError('Field "' + fieldName + '" is mandatory for Lumenaza API');
                    break;
                }

                if (fieldName == 'previous_provider' && mapLumenazaFields.get('subscription_reason') == 'E03' && value.length() == 0) {
                    this.setError('Field "' + fieldName + '" must be set if subscription_reason ist E03');
                    break;
                }
                if (fieldName == 'salutation' && value != 'Herr' && value != 'Frau') {
                    this.setError('Field "' + fieldName + '" must be "Herr" or "Frau"');
                    break;
                }
                if (fieldName == 'tariff_type' && !validTariffTypes.contains(value)) {
                    this.setError('Field "' + fieldName + '" must be one of the following: ' + String.join(new List<String>(validTariffTypes), ', '));
                    break;
                }
                if (fieldName == 'titel' && value != '' && value != 'Dr.' && value != 'Prof.' && value != 'Prof. Dr.') {
                    this.setError('Field "' + fieldName + '" must be "Dr.", "Prof." or "Prof. Dr."');
                    break;
                }
                if (fieldName == 'email' && Pattern.compile('[^@\\s]+@[^@\\s]+\\.[a-zA-Z]{2,}').matcher(value).matches() == false) {
                    this.setError('Invalid email address');
                    break;
                }
            }

            // Validation according selected tariff_type and upsertMode (2017-03-23, SOBCRM-852)
            Set<String> lsetTariffTypes = new Set<String>{
                'household',
                'sonnenFlat',
                'sonnenCity',
                'sonnenStrom' // since 2017-06-14, SOBCRM-984
            };

            Set<String> lsetValidFields = this.validFieldsPerUpsertMode.get(this.getUpsertMode());

            String sTariffType = mapLumenazaFields.get('tariff_type');

            if (lsetTariffTypes.contains(sTariffType)) {

                if (lsetValidFields.contains('saas_customer_id') && mapLumenazaFields.get('saas_customer_id') == NULL || mapLumenazaFields.get('saas_customer_id') == '') {
                    this.setError('Field "saas_customer_id" at type "' + sTariffType + '" is mandatory');
                    break;
                }
                if (lsetValidFields.contains('sepa_reference') && mapLumenazaFields.get('sepa_reference') == NULL || mapLumenazaFields.get('sepa_reference') == '') {
                    this.setError('Field "sepa_reference" at type "' + sTariffType + '" is mandatory');
                    break;
                }
                if ((sTariffType == 'sonnenFlat' || sTariffType == 'sonnenCity')
                    && lsetValidFields.contains('free_amount')
                    && (mapLumenazaFields.get('free_amount') == NULL || Decimal.valueOf(mapLumenazaFields.get('free_amount')) <= 0)) {
                    this.setError('Field "free_amount" at type "' + sTariffType + '" is mandatory');
                    break;
                }
                if (sTariffType == 'sonnenFlat'
                    && lsetValidFields.contains('consumption_before_battery_installation')
                    && (mapLumenazaFields.get('consumption_before_battery_installation') == NULL || Decimal.valueOf(mapLumenazaFields.get('consumption_before_battery_installation')) <= 0)) {
                    this.setError('Field "consumption_before_battery_installation" at type "' + sTariffType + '" is mandatory');
                    break;
                }
            }

            break;
        }

        if (this.hasError()) {
            System.debug(sDebugHere + 'Validation error occurred: ' + this.getError());
            return FALSE;
        }

        System.debug(sDebugHere + 'Validation OK');

        return TRUE;
    }

    /**
     * Alias for isAccountLumenazaCustomer()
     */
    public Boolean getIsAccountLumenazaCustomer() {
        return this.isAccountLumenazaCustomer();
    }

    /**
     * Alias for checkOnMultipleContractsByAccountIds(Set<Id> lsetAccountIds)
     */
    public static Map<Id,List<String>> checkOnMultipleContractsByAccountIds(Id idAccount) {
        return checkOnMultipleContractsByAccountIds(new Set<Id>{idAccount});
    }

    /**
     * Determine if Contract's Account already has a Contract at Lumenaza.
     * This makes a difference as the customer_no is then registered already and
     * creation of the a new Contract would fail with an "saas_customer_id not unique"
     * error.
     */
    public static Map<Id,List<String>> checkOnMultipleContractsByAccountIds(Set<Id> lsetAccountIds) {

        Map<Id,List<String>> mapAccountIdToLumenazaCustomerIds = new Map<Id,List<String>>();

        if (!lsetAccountIds.isEmpty()) {

            List<AggregateResult> oAggregateResults = new List<AggregateResult>([
                SELECT
                    AccountId,
                    LumenazaCustomerId__c,
                    COUNT(Id) countOfContracts
                FROM
                    Contract
                WHERE
                AccountId IN :lsetAccountIds AND
                LumenazaCustomerId__c != NULL
                GROUP BY
                        AccountId,
                        LumenazaCustomerId__c
            ]);

            // Sort LumenazaCustomerIds to AccountIds
            for (AggregateResult oAggregateResult : oAggregateResults) {

                Id idAccount = (Id)oAggregateResult.get('AccountId');
                String sLumenazaCustomerId = (String)oAggregateResult.get('LumenazaCustomerId__c');

                if (mapAccountIdToLumenazaCustomerIds.get(idAccount) == NULL) {
                    mapAccountIdToLumenazaCustomerIds.put(idAccount, new List<String>());
                }
                mapAccountIdToLumenazaCustomerIds.get(idAccount).add(sLumenazaCustomerId);
            }

            for (Id idAccount : lsetAccountIds) {
                if (mapAccountIdToLumenazaCustomerIds.get(idAccount) == NULL) {
                    mapAccountIdToLumenazaCustomerIds.put(idAccount, new List<String>());
                }
            }
        }

        return mapAccountIdToLumenazaCustomerIds;
    }

    /**
     * Returns if this Contract's account is already a
     * Lumenaza customer
     */
    public Boolean isAccountLumenazaCustomer() {

        String sDebugHere = DEBUG_HEADER + '.isAccountLumenazaCustomer() - ';

        // Should never be the case!
        if (this.contract.AccountId == NULL) {
            return FALSE;
        }

        if (this.isLumenazaCustomer == NULL) {

            Id idAccount = this.contract.AccountId;
            Map<Id,List<String>> mapAccountIdToLumenazaCustomerIds = checkOnMultipleContractsByAccountIds(idAccount);

            if (mapAccountIdToLumenazaCustomerIds.get(idAccount).size() > 1) {

                List<String> listLumenazaCustomerIds = mapAccountIdToLumenazaCustomerIds.get(idAccount);

                String sError = 'Contract\'s (' + this.contract.Id + ') Account (' + this.contract.AccountId + ') has Contracts with multiple Lumenaza Customer IDs (' + String.join(listLumenazaCustomerIds, ', ') + ')!';

                try {
                    Case oCase = this.prepareErrorCase();

                    oCase.Contract__c = this.contract.Id;
                    oCase.AccountId = this.contract.AccountId;
                    oCase.ContactId = this.contract.CustomerSignedId;

                    oCase.subject = 'Error at Lumenaza Sync for Contract';
                    oCase.description  = 'Error: ' + sError + '\n\n';
                    insert oCase;
                }
                catch (Exception e) {
                }

                throw new LumenazaContractException(sError);
            }

            this.isLumenazaCustomer = !mapAccountIdToLumenazaCustomerIds.get(idAccount).isEmpty();

            // Set customer ID
            if (this.isLumenazaCustomer) {
                this.lumenazaCustomerIdOfExistingContract = mapAccountIdToLumenazaCustomerIds.get(idAccount).get(0);
                System.debug(sDebugHere + 'Set lumenazaCustomerIdOfExistingContract to "' + this.lumenazaCustomerIdOfExistingContract + '"');
            }
        }

        return this.isLumenazaCustomer;
    }

    /**
     * Sets if the Contract's Customer is already a Lumenaza Customer
     */
    public void setIsAccountLumenazaCustomer(Boolean isAccountLumenazaCustomer, String lumenazaCustomerId) {
        System.debug(DEBUG_HEADER + '.setIsAccountLumenazaCustomer() - Contract\'s Account is already Lumenaza Customer: ' + (isAccountLumenazaCustomer ? 'YES (set lumenazaCustomerIdOfExistingContract to "' + lumenazaCustomerId + '")' : 'NO'));
        this.isLumenazaCustomer = isAccountLumenazaCustomer;
        this.lumenazaCustomerIdOfExistingContract = lumenazaCustomerId;
    }

    /**
     * Returns the Lumenaza Customer ID
     */
    public String getLumenazaCustomerId() {
        return (this.lumenazaCustomerId != NULL && this.lumenazaCustomerId.length() > 0) ? this.lumenazaCustomerId : NULL;
    }

    /**
     * Returns the Lumenaza Contract ID
     */
    public String getLumenazaContractId() {
        return (this.lumenazaContractId != NULL && this.lumenazaContractId.length() > 0) ? this.lumenazaContractId : NULL;
    }

    /**
     * Returns the Lumenaza Contract ID of an existing Customer at Lumenaza
     *
     * This is the case if the Customer already has made a previous Contract
     */
    public String getLumenazaCustomerIdOfExistingContract() {
        this.isAccountLumenazaCustomer(); // to init an existing Customer ID at Lumenaza
        return (this.lumenazaCustomerIdOfExistingContract != NULL && this.lumenazaCustomerIdOfExistingContract.length() > 0) ? this.lumenazaCustomerIdOfExistingContract : NULL;
    }

    /**
     * Returns the special action (e.g. revoke)
     */
    public String getSpecialAction() {
        return this.specialAction;
    }

    public class LumenazaContractException extends Exception {}
}
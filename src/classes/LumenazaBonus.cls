/**
 * Lumenaza Bonus object
 *
 * Changelog:
 *
 * v1.2.0 (MSB 2017-10-23)
 * - Added field "apply_to" (SOBCRM-1090)
 *
 * v1.1.0 (MSB 2016-10-05)
 * - Revised for using Lumenaza API v3 (SOBCRM-666)
 *
 * v1.0.0 (2016-04-27)
 * - Initial
 *
 * @author  Marko Schmalenbach <marko@die-interaktiven.de>
 * @version 1.1.0 (2016-10-05)
 */
public class LumenazaBonus extends LumenazaObject {
    
    private Bonus__c bonus;

    private String lumenazaCustomerId; // same as consumerId
        
    /**
     * Init LumenazaFields
     */
    protected override void initLumenazaFields() {
     
        this.lumenazaFields = new Map<String,String>{
            'amount_kwh'       => NULL, // float (mandantory if amount_euro is empty), kwH
            'amount_euro'      => NULL, // float (mandantory if amount_kwh is empty), EUR gross
            'contract_id'      => NULL, // string (mandatory), the ID of the contract to which the bonus is associated
            'start_date'       => NULL, // string (mandatory), date format: YYYY-MM-DD
            'number_of_months' => NULL, // integer (mandatory), length of bonus we payed
            'bonusID'          => NULL, // string (mandatory), a unique identifier for this bonus
            'bonus_type'       => NULL, // string (mandatory, values: periodical, oneshot
            'display_name'     => NULL, // string (mandatory), display name for customer/invoices. This should be the name used in the market campaign for better recognition by the customer.
            'apply_to'         => NULL  // string (optional), if given apply bonus to special part of product; values are: consumption, community_fee, base_fee
        };
    }
    
    /**
     * Instantiate LumenazaBonus by Bonus__c
     */
    public LumenazaBonus(Bonus__c bonus) {
        
        if (bonus == NULL) {
            throw new LumenazaObjectException('Bonus object is null');    
        }        
        if (bonus.Id == NULL) {
            throw new LumenazaObjectException('Only existing Bonuses with ID can be passed');    
        }        
        this.initLumenazaFields();

        // Init by bonus
        this.bonus = bonus;                
        this.sObjectId = this.bonus.Id;

        this.lumenazaCustomerId = this.bonus.Lumenaza_consumer_id__c;

        System.debug('LumenazaBonus - Bonus ' + bonus);
        
        this.setLumenazaFieldsFromObject(bonus);
    }
    
    /**
     * Init by bonus ID
     */
    public LumenazaBonus(Id bonusId) {        
        this((Bonus__c)Database.query('SELECT ' + DiaUtilities.returnAllFieldsAsString('Bonus__c') + ' FROM Bonus__c WHERE Id = :bonusId'));        
    }       
    
    /**
     * Init future upsert
     */
    public override void initFutureUpsert() {
        if (Test.isRunningTest() == true) {
            new LumenazaBonus(this.sObjectId).persist();                
        }
        else {
            LumenazaBonus.futureUpsert(this.sObjectId);            
        }
    }

    /**
     * Future upsert of a LumenazaBonus by a bonus ID
     */
    @future(callout=true)
    public static void futureUpsert(Id bonusId) {        
        System.debug('LumenazaBonus - futureUpsert() with bonus ' + bonusId);        
        new LumenazaBonus(bonusId).persist();
    }    
    
    /**
     * Persist this object
     * 
     * @return Boolean Success
     */
    public override Boolean persist() {
        
        // Validate and if false write to bonus
        if (this.validate() == false) {
            return false;
        }
                
        Bonus__c bonus = this.bonus;
        System.debug('LumenazaBonus - persist(): bonus ' + bonus);
                
        // Set Request time
        bonus.Lumenaza_ApiRequestTime__c = System.now();
        
        String error = '';
        String errorDescription = '';
        
        // Insert bonus via API
        try {            
            LumenazaApi api = new LumenazaApi();
            LumenazaApi.LumenazaApiResponse lumenazaResponse = api.addBonus(this);
            
            System.debug('LumenazaBonus - Got Lumenaza API Response: ' + lumenazaResponse);
                
            // Set request info
            bonus.Lumenaza_ApiRequest__c = lumenazaResponse.requestInfo;
                
            if (lumenazaResponse.success == false) {
                bonus.Lumenaza_ApiResponse__c = lumenazaResponse.error;
                error = lumenazaResponse.error;
            }   
            else {

                bonus.Lumenaza_ApiResponse__c = lumenazaResponse.response.getBody();
                
                if (lumenazaResponse.resultMap != NULL) {
                    
                    Map<String,String> resultMap = lumenazaResponse.resultMap;

                    /*
                    if (resultMap.containsKey('contract_id')) {
                        bonus.xxx = resultMap.get('contract_id');                    
                    }
                    */
                }                
            }
                    
            if (lumenazaResponse.response != NULL) {
                
                if (Test.isRunningTest() && bonus.Lumenaza_ApiStatusCode__c == 'TEST') {
                    System.debug('LumenazaBonus - Set a fake error to raise a case');
                    error = 'TESTERROR';
                }
                
                bonus.Lumenaza_ApiStatusCode__c = String.valueOf(lumenazaResponse.response.getStatusCode());
            }
            else {
                // Error on NULL response
                System.debug('LumenazaBonus - lumenazaResponse.response is NULL');                
                error = 'The lumenazaResponse.response was NULL so the response could not be written to the Bonus';
                bonus.Lumenaza_ApiResponse__c = error;
                errorDescription = '\n\nLumenazaResponse: ' + lumenazaResponse;
            }            
        }
        catch (Exception e) {            
            bonus.Lumenaza_ApiResponse__c = e.getMessage();
            error = e.getMessage() + ' ' + e.getStackTraceString();
        }
        
        try {
            TriggerHandler.bypass('LumenazaBonusTriggerHandler');
            System.debug('LumenazaBonus - Update bonus with bypassing LumenazaBonusTriggerHandler: ' + bonus);        
            update bonus;    
            TriggerHandler.clearBypass('LumenazaBonusTriggerHandler');
        }
        catch (Exception e) {
            error = e.getMessage() + ' ' + e.getStackTraceString();
        }
        
        // Open case on error
        if (error.length() > 0) {
            Case errorCase = new Case();
            errorCase.subject = 'Error at Lumenaza Sync for Bonus';
            errorCase.description  = 'Error: ' + error + '\n\n';
            errorCase.description += 'Bonus ' + System.Url.getSalesforceBaseUrl().toExternalForm() + '/' + bonus.Id; 
            errorCase.description += errorDescription;
            insert errorCase;            
        }

        return true;
    }
                                
    /**
     * Is called by LumenazaApi to check if object needs an update.
     * In this case bonus is always only inserted
     */
    public override Boolean needsUpdate() {
        
        if (!this.bonus.IsSyncableToLumenaza__c) {
            System.debug('LumenazaBonus - needsUpdate(): IsSyncableToLumenaza__c is not true: no update');
            return false;
        }
        
        return true;
    }
    
    /**
     * Validates the object
     */
    public override Boolean validate() {
        
        System.debug('LumenazaBonus - validate() fields: ' + this.lumenazaFields);
                
        for (String fieldName : this.lumenazaFields.keySet()) {
            
            String value = (this.lumenazaFields.get(fieldName) == NULL) ? '' : this.lumenazaFields.get(fieldName).trim();
                        
            if (
                (
                    fieldName == 'amount' ||
                    fieldName == 'contract_id' ||
                    fieldName == 'start_date' ||
                    fieldName == 'number_of_months' ||
                    fieldName == 'bonusID' ||
                    fieldName == 'bonus_type' ||
                    fieldName == 'display_name'
                ) && value.length() == 0) {
                this.setError('Field "' + fieldName + '" is mandatory for Lumenaza API');
                return false;
            }
        }
        
        if ((this.lumenazaFields.get('amount_kwh') == NULL || this.lumenazaFields.get('amount_kwh').length() == 0) && 
            (this.lumenazaFields.get('amount_euro') == NULL || this.lumenazaFields.get('amount_euro').length() == 0)) {
            this.setError('Either amount_kwh or amount_euro is mandatory for Lumenaza API');
            return false;               
        }
        if (this.lumenazaFields.get('amount_kwh') != NULL && this.lumenazaFields.get('amount_kwh').length() != 0 && 
            this.lumenazaFields.get('amount_euro') != NULL && this.lumenazaFields.get('amount_euro').length() != 0) {
            this.setError('Specify either amount_kwh OR amount_euro for Lumenaza API');
            return false;               
        }
        
        return true;
    } 
    
    /**
     * Return the bonus object
     */
    public Bonus__c getBonus() {
        return this.bonus;
    }
    
    /**
     * Returns the bonus' contractId
     */
    public String getLumenazaContractId() {
        if (this.bonus != NULL) {
            return this.bonus.Lumenaza_contract_id__c;
        }
        return NULL;
    }

    /**
     * Returns the Lumenaza customer ID (consumer ID)
     */
    public String getLumenazaCustomerId() {
        return this.lumenazaCustomerId;
    }
}
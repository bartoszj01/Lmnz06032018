public class LumenazaBonusTriggerHandler extends TriggerHandler {
    
    public override void afterInsert() {
        this.upsertLumenazaBonus();
    }
    
    public override void afterUpdate() {
        this.upsertLumenazaBonus();
    }
    
	public void upsertLumenazaBonus() {
        
        Set<LumenazaObject> lumenazaBonusesToInsert = new Set<LumenazaObject>();
                
        for (Bonus__c bonusAfter : (List<Bonus__c>) Trigger.new) {            
            // Instantiate a LumenazaBonus by a Bonus__c and add to list
			lumenazaBonusesToInsert.add(new LumenazaBonus(bonusAfter));
        }
                
        // If any LumenazaContract validates to false everything is rolled
        // back otherwise Contracts will be upserted if API Sync is active       
        if (lumenazaBonusesToInsert.size() > 0 && LumenazaApi.initUpsert(lumenazaBonusesToInsert) == false) {
            
            for (LumenazaObject lumenazaObject : lumenazaBonusesToInsert) {
                
                LumenazaBonus lumenazaBonus = (LumenazaBonus)lumenazaObject;
                
                if (lumenazaBonus.hasError() == true) {
               		lumenazaBonus.getBonus().addError(lumenazaBonus.getError());
                }
            }    
        }           
    }
}
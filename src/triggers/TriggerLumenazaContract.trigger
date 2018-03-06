trigger TriggerLumenazaContract on Contract (after update, before insert, before update) {
	new LumenazaContractTriggerHandler().run();
}
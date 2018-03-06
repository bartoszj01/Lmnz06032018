/**
 * LumenazaInboundMailHandler
 *
 * --- Changelog
 *
 * 1.1 2017-12-27
 *
 * @version 1.1
 */
public class LumenazaInboundMailHandler implements Messaging.InboundEmailHandler {

    private List<LumenazaEmailTemplates__c> templates;
    
    public static final String lumenazaContractIdRegex = '\\b([P|C][0-9]+-[0-9]+)\\b'; // since SOBCRM-363
    public static final String testContractId = 'P16000001-1';
    
    /**
     * Constructor
     */
    public LumenazaInboundMailHandler() {

        // Get all email templates
        this.templates = LumenazaEmailTemplates__c.getall().values();
        
        if (this.templates == NULL) {
            throw new LumenazaInboundMailHandlerException('LumenazaInboundMailHandler - No LumenazaEmailTemplates found');
        }        
    }

    /**
     * Implements interface method "handleInboundEmail"
     */
    public Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {

		Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();

		System.debug('LumenazaInboundMailHandler - Try to route mail from ' + email.fromAddress + ' with subject "' + email.subject + '"');
        
        String mailTemplateId;
        String ruleName;
        String mailSenderDisplayName;
        String mailSenderId;

        try {

            Boolean templateFound = false;
            
            for (LumenazaEmailTemplates__c template : this.templates) {
                
                Matcher patternMatcher = Pattern.compile(template.EmailSubjectRegex__c).matcher(email.subject);
                
                System.debug('LumenazaInboundMailHandler - Check "' + template.EmailSubjectRegex__c + '" against ' + email.subject);
                
                if (patternMatcher.matches()) {                    
                    
					System.debug('LumenazaInboundMailHandler - Matching rule is "' + template.InternalName__c + '"');
                    
                    mailTemplateId        = template.EmailTemplateId__c;
                    ruleName              = template.InternalName__c;
                    mailSenderDisplayName = template.EmailSenderDisplayName__c;
                    mailSenderId          = template.EmailSenderId__c;
                    
                    templateFound = true;
                    break;
                }
            }

            // Search for contract ID
            String contractId = '';
            
           	// Try to find the Lumenaza contract ID in
           	
           	// Subject
            contractId = this.searchLumenazaContractId(email.subject);            
            if (contractId == '') {                
                // Text body
            	contractId = this.searchLumenazaContractId(email.plainTextBody);                                
                if (contractId == '') {
                    // HTML body
                    contractId = this.searchLumenazaContractId(email.htmlBody);
            		if (contractId == '') {
                        throw new LumenazaInboundMailHandlerException('LumenazaInboundMailHandler - Contract ID could not be found');
                    }
                }
            }

			System.debug('LumenazaInboundMailHandler - Lumenaza Contract ID is "' + contractId + '"');

            List<Contract> contracts = [SELECT Id, Type__c, LumenazaContractId__c, ContractingPartyEmail__c FROM Contract WHERE LumenazaContractId__c = :contractId];



            if (contracts.isEmpty()) {
				throw new LumenazaInboundMailHandlerException('LumenazaInboundMailHandler - Contract with LumenazaContractId__c "' + contractId + '" not found');
            }

            Contract contract = contracts.get(0);

            // If we use template by Contract.Type__c - use it instead (https://interaktiv.jira.com/browse/SOBCRM-1128)
            for (LumenazaEmailTemplates__c template: this.templates) {
                Boolean contractTypeTemplate = template.EmailSubjectRegex__c.length() > 17 && template.EmailSubjectRegex__c.substring(0, 17) == 'Contract.Type__c=';
                if (contractTypeTemplate && template.EmailSubjectRegex__c.substring(17) == contract.Type__c) {
                    mailTemplateId        = template.EmailTemplateId__c;
                    ruleName              = template.InternalName__c;
                    mailSenderDisplayName = template.EmailSenderDisplayName__c;
                    mailSenderId          = template.EmailSenderId__c;
                    templateFound = true;
                    break;
                }
            }

            if (templateFound == false) {
                throw new LumenazaInboundMailHandlerException('LumenazaInboundMailHandler - No matching LumenazaEmailTemplates entry found to handle mail');
            }


            if (contract.ContractingPartyEmail__c == NULL) {
				throw new LumenazaInboundMailHandlerException('LumenazaInboundMailHandler - Contract has no email in ContractingPartyEmail__c');                                
            }
            
            String mailTo = contract.ContractingPartyEmail__c;                        
			System.debug('LumenazaInboundMailHandler - Salesforce Contract ID is "' + contract.Id + '" with email "' + mailTo + '"');		
                        
            // Add attachments to contract and activity                        
        	List<Attachment> attachments = new List<Attachment>();
            
            if (email.binaryAttachments != NULL && email.binaryAttachments.size() > 0) {
                
				System.debug('LumenazaInboundMailHandler - Handle ' + email.binaryAttachments.size() + ' attachment(s)');		
                
                for (Messaging.Inboundemail.BinaryAttachment binaryAttachment: email.binaryAttachments) {                
                    
                    attachments.add(new Attachment(
                        Name = binaryAttachment.FileName,
                        Body = binaryAttachment.Body,
                        ParentId = contract.Id
                    ));                                
                    System.debug('LumenazaInboundMailHandler - Add attachment "' + binaryAttachment.fileName + '"');		
                }
                if (attachments.size() > 0) {
                    insert attachments;
                }
            }               
            else {
				System.debug('LumenazaInboundMailHandler - No attachments found');
            }
            
            // Create an activity/task
            String subject     = email.subject + ' (-> ' + ruleName + ')';  
            
            String description  = 'EMAIL RULE:\n' + ruleName + '\n\n';                 
                   description += 'EMAIL TEMPLATE:\n' + this.makeInternalUrlToId(mailTemplateId) + '\n\n';
            
            if (attachments.size() > 0) {
            	description += 'ATTACHMENT:\n';
                for (Attachment attachment : attachments) {
                	description += attachment.Name + ' (' + this.makeInternalUrlToId(attachment.Id) + ')\n';    
                }
            	description += '\n';
            }
            
            description += 'CONTENT:\n' + email.plainTextBody;
            
            Task task = new Task(
                Subject      = subject.length() > 255 ? subject.substring(0, 255) : subject,
                Type         = 'Email',
                Description  = description.length() > 32000 ? description.substring(0, 32000) : description,
                WhatId       = contract.Id,
                Status       = 'Completed',
                ActivityDate = System.today()
            );
			insert task;

            this.sendMergeTemplateMailWithoutTargetObject(mailTo, Id.valueOf(mailTemplateId), contract.Id, attachments, mailSenderDisplayName, mailSenderId);
        }
        catch(Exception e) {
            
            String traceString = e.getStackTraceString();
            
            Case emailCase = new Case();
            emailCase.subject = 'Error on handling email from ' + email.fromAddress;
			emailCase.description  = e.getMessage() + (e.getCause() != NULL ? ' ' + e.getCause() : '')  + (e.getLineNumber() > 0 ? ' in line #' + e.getLineNumber() : '');
            emailCase.description += '\n\nSubject:\n' + email.subject;
            emailCase.description += '\n\nEmail body:\n' + email.plainTextBody;
            if (traceString.length() > 0) {
				emailCase.description += '\n\nTrace:\n' + traceString;
            }
            insert emailCase;
            
            // Add attachments (SOBCRM-167)
        	List<Attachment> caseAttachments = new List<Attachment>();
            
            if (email.binaryAttachments != NULL && email.binaryAttachments.size() > 0) {                                
                for (Messaging.Inboundemail.BinaryAttachment binaryAttachment: email.binaryAttachments) {
                    caseAttachments.add(new Attachment(
                        Name = binaryAttachment.FileName,
                        Body = binaryAttachment.Body,
                        ParentId = emailCase.Id
                    ));
                }
                if (caseAttachments.size() > 0) {
                    insert caseAttachments;
                }
            }               
        }
        
        return result;
    }
    
    /**
     * Search for a Lumenaza contract ID according
     * to the defined lumenazaContractIdRegex
     */
    private String searchLumenazaContractId(String contentToSearchIn) {
        
        String lumenazaContractId = '';
        
        if (contentToSearchIn == NULL) {
            return lumenazaContractId;
        }

		System.debug('LumenazaInboundMailHandler - searchLumenazaContractId() Search via regex "' + lumenazaContractIdRegex + ' in: ' + contentToSearchIn);		        
        Matcher patternMatcher = Pattern.compile(lumenazaContractIdRegex).matcher(contentToSearchIn);
        
        if (patternMatcher.find() == true) {
            lumenazaContractId = patternMatcher.group(0);
        }
                
        return lumenazaContractId;
    }
    
    /**
     * Creates an internal Salesforce URL by an ID
     */
    private String makeInternalUrlToId(String idToLinkTo) {
    	return System.Url.getSalesforceBaseUrl().toExternalForm() + '/' + idToLinkTo;
    }
    
    /**
     * Sends a merge template mail without having a contact, 
     * lead or something as target object
     */
    private void sendMergeTemplateMailWithoutTargetObject(String mailTo, Id templateId, Id whatId, List<Attachment> attachments, String mailSenderDisplayName, String mailSenderId) {    
        
        List<Messaging.SingleEmailMessage> dummyEmailList = new List<Messaging.SingleEmailMessage>();
        Messaging.SingleEmailMessage dummyEmail = new Messaging.SingleEmailMessage();
        
        Savepoint sp = Database.setSavepoint();

		System.debug('LumenazaInboundMailHandler - sendMergeTemplateMailWithoutTargetObject() Try to send mail to: ' + mailTo);		        
        
        try {            
            // Create a dummy account and contact
            Datetime now =  Datetime.now();
            String dummyName = 'Dummy ' + now.getTime();
            
            Account dummyAccount = new Account(Name = dummyName);
            insert dummyAccount;        
            Contact dummyContact = new Contact(LastName = dummyName, Email = mailTo, AccountId = dummyAccount.Id);
            insert dummyContact;
                    
            System.debug('LumenazaInboundMailHandler - sendMergeTemplateMailWithoutTargetObject() Created dummy Account: ' + dummyAccount);		        
            System.debug('LumenazaInboundMailHandler - sendMergeTemplateMailWithoutTargetObject() Created dummy Contact: ' + dummyContact);		        
            
            // Construct a dummy email by template and the dummy contact            
            dummyEmail.setTemplateId(templateId);
            dummyEmail.setWhatId(whatId);
            dummyEmail.setTargetObjectId(dummyContact.Id);
            dummyEmail.setToAddresses(new List<String>{mailTo});        
            dummyEmailList.add(dummyEmail);
    
            System.debug('LumenazaInboundMailHandler - sendMergeTemplateMailWithoutTargetObject() templateId: ' + templateId + ', whatId: ' + whatId);		        
            System.debug('LumenazaInboundMailHandler - sendMergeTemplateMailWithoutTargetObject() dummyEmail: ' + dummyEmail);		        
            
            // Send the emails in a transaction, then roll it back
            Messaging.sendEmail(dummyEmailList);
        }
        catch (Exception e) {
            // Catch Exception so make sure that rollback is forced!
        	Database.rollback(sp);
            // Throw own exception
            throw new LumenazaInboundMailHandlerException(e);
        }
        
        Database.rollback(sp);
                
        // Get "send" rendered mail and create a new Mail by this
        dummyEmail = dummyEmailList.get(0);
            
        Messaging.SingleEmailMessage emailToSend = new Messaging.SingleEmailMessage();
       
        //emailToSend.setToAddresses(dummyEmail.getToAddresses());
        emailToSend.setToAddresses(new List<String>{mailTo});
        emailToSend.setPlainTextBody(dummyEmail.getPlainTextBody());
        emailToSend.setHTMLBody(dummyEmail.getHTMLBody());
        emailToSend.setSubject(dummyEmail.getSubject());
        
        if (mailSenderId != NULL && mailSenderId.length() > 0) {
        	emailToSend.setOrgWideEmailAddressId(mailSenderId);
        }
        else if (mailSenderDisplayName != NULL && mailSenderDisplayName.length() > 0) {
        	emailToSend.setSenderDisplayName(mailSenderDisplayName);            
        }
        
        // Add attachments
        List<Messaging.EmailFileAttachment> emailAttachments = new List<Messaging.EmailFileAttachment>();
        
        if (attachments.size() > 0) {            
            for (Attachment attachment : attachments) {
        		Messaging.EmailFileAttachment emailAttachment = new Messaging.EmailFileAttachment();
                emailAttachment.setBody(attachment.Body);
                emailAttachment.setFileName(attachment.Name);
                emailAttachments.add(emailAttachment);
            }
            emailToSend.setFileAttachments(emailAttachments);
        }

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{emailToSend});
    }
    
    /**
     * Own exception
     */
   	public class LumenazaInboundMailHandlerException extends Exception {}    
}
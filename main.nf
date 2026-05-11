#!/usr/bin/env nextflow
/*
========================================================================================
    genepi/nf-imputationserver
========================================================================================
    Github : https://github.com/genepi/nf-imputationserver
    Author: Lukas Forer & Sebastian Schönherr
    ---------------------------
*/

if (params.refpanel_yaml){
    params.refpanel = RefPanelUtil.loadFromFile(params.refpanel_yaml)
}

requiredParams = [
    'project', 'files', 'output', 'refpanel'
]

for (param in requiredParams) {
    if (params[param] == null) {
      exit 1, "Parameter ${param} is required."
    }
}

//TODO create json validation file
def phasing_engine = params.phasing.engine

if (phasing_engine != 'eagle' && phasing_engine != 'beagle' && phasing_engine != 'no_phasing' ) {
    println "::error:: For phasing, only options 'eagle', 'beagle' or 'no_phasing' are allowed."
    exit 1
}


// create random password when not set by user
if (params.password == null) {
    params.encryption_password = PasswordCreator.createPassword()   
} else {
    params.encryption_password = params.password
}

//set default population to "off" when allele_frequency_population is null
params.population = params.allele_frequency_population ?: "off"

Channel
    .fromPath(params.files)
    .set {files}

files.ifEmpty {
    println "::error:: No vcf.gz input files detected."
    exit 1
}

// Find site files from full pattern and make site file pattern relative
params.refpanel.sites_pattern = "${params.refpanel.sites}"
params.refpanel.sites = "./${file(params.refpanel.sites).fileName}"

site_files_ch = Channel.of(1..22, 'X', 'MT')
    .map {
        it -> 
            def sites_file = file(PatternUtil.parse(params.refpanel.sites_pattern, [chr: it]))
            def sites_file_index = file(PatternUtil.parse(params.refpanel.sites_pattern+ ".tbi", [chr: it]))
            
            if(!sites_file.exists()){
                return null;
            }  

            if(sites_file.exists() && !sites_file_index.exists()){
                error "Missing tabix index for " + sites_file
            }  
        
            return tuple(sites_file, sites_file_index); 
    }

include { INPUT_VALIDATION } from './workflows/input_validation'
include { QUALITY_CONTROL } from './workflows/quality_control'
include { PHASING } from './workflows/phasing'
include { IMPUTATION } from './workflows/imputation'
include { ENCRYPTION } from './workflows/encryption'
include { ANCESTRY_ESTIMATION } from './workflows/ancestry_estimation'
include { PGS_CALCULATION } from './workflows/pgs_calculation'

workflow {

    println "Welcome to ${params.service.name} (${workflow.manifest.version})"

    if (params.imputation.enabled){

        INPUT_VALIDATION()

        QUALITY_CONTROL(
            INPUT_VALIDATION.out.validated_files,
            INPUT_VALIDATION.out.validation_report,
            site_files_ch.collect()
        )
       
       // check if QC chunks exist in case QC failed
       QUALITY_CONTROL.out.qc_metafiles.ifEmpty {
       error "QC step failed"
       } 

        if (params.mode == 'imputation') {

            phased_ch =  QUALITY_CONTROL.out.qc_metafiles

            if (phasing_engine != 'no_phasing') { 

                PHASING(
                    QUALITY_CONTROL.out.qc_metafiles
                )

                phased_ch = PHASING.out.phased_ch

            }
                 
            IMPUTATION(
                phased_ch
            )
            
            if (params.merge_results === true) {
                ENCRYPTION(
                    IMPUTATION.out.groupTuple()
                )
            }
            
        }
    }
    
    // handles empty objects (e.g. cloudgene)
    ancestry_enabled = params.ancestry != null && params.ancestry != "" && params.ancestry.enabled

    if (ancestry_enabled) {
        ANCESTRY_ESTIMATION()
    }

    if (params.pgs.enabled) {

        PGS_CALCULATION(
            IMPUTATION.out,
            ancestry_enabled ? ANCESTRY_ESTIMATION.out : Channel.empty()
        )
        
    }
    
}

workflow.onComplete {
    //TODO: use templates
    //TODO: move in EmailHelper class
        if (!workflow.success) {
            def statusMessage = (workflow.exitStatus != null || workflow.errorReport == "QC step failed") 
            ? "failed" 
            : "canceled"

            def statusText = (statusMessage == "failed") 
            ? "Your job failed." 
            : "Your job has been canceled."
                
            if (params.send_mail && params.user.email != null) {
                sendMail{
                    to "${params.user.email}"
                    subject "[${params.service.name}] Job ${params.project} ${statusMessage}" 
                    body "Dear ${params.user.name},\n${statusText}\n\nMore details can be found at the following link: ${params.service.url}/index.html#!jobs/${params.project_id}"
                }
            }
        println "::error:: Imputation job ${statusMessage}." 
        return
    }

    //submit counters for successful imputation jobs  
    if (params.mode == 'imputation') {
        println "::submit-counter name=samples::"
        println "::submit-counter name=genotypes::"
        println "::submit-counter name=chromosomes::"
        println "::submit-counter name=runs::"

        println "::set-value-and-submit name=reference_panel::${params.refpanel.id}"
        println "::set-value-and-submit name=phasing_engine::${phasing_engine}"
        println "::set-value-and-submit name=genome_build::${params.build}"
    }

    // imputation job
    if (params.merge_results === true && params.encryption.enabled === true) {

        if (params.send_mail && params.user.email != null) {
            sendMail{
                to "${params.user.email}"
                subject "[${params.service.name}] Job ${params.project} is complete"
                body "Dear ${params.user.name},\nYour imputation job has finished succesfully. The password for the imputation results is: ${params.encryption_password}\n\nYou can download the results from the following link: ${params.service.url}/index.html#!jobs/${params.project_id}"
            }
            println "::message:: Data have been exported successfully. We have sent a notification email to <b>${params.user.email}</b>"
        } else {
            println "::message:: Data have been exported successfully. We encrypted the results with the following password: <b>${params.encryption_password}</b>"
        }
        return
    }

    //PGS job
    if (params.send_mail && params.user.email != null) {
        sendMail{
            to "${params.user.email}"
            subject "[${params.service.name}] Job ${params.project} is complete"
            body "Dear ${params.user.name},\nYour PGS job has finished successfully.\n\nYou can download the results from the following link: ${params.service.url}/index.html#!jobs/${params.project_id}"
        }
        println "::message:: Data have been exported successfully. We have sent a notification email to <b>${params.user.email}</b>"
    } else {
        println "::message:: Data have been exported successfully."
    }

}

// Emit a structured error descriptor under `${params.logs}/fedimpute_error.json`
// (see docs/PIPELINE_ERROR_SCHEMA.md in the fedimpute repo). The FedImpute
// backend reads this file via the WES outputs endpoint and renders a typed
// error UI with a "Error docs ↗" deep-link to the workflow's docs site;
// if the file is absent the backend falls back to parsing stdout.
def emitStructuredError(Map err) {
    try {
        def logsPath
        if (params.containsKey('logs') && params.logs) {
            logsPath = "${params.logs}"
        } else if (params.containsKey('output') && params.output) {
            logsPath = "${params.output}/logs"
        } else {
            logsPath = "${workflow.launchDir}/logs"
        }
        def logsDir = file(logsPath)
        logsDir.mkdirs()
        def payload = [version: "1"] + err
        file("${logsPath}/fedimpute_error.json").text =
            groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(payload))
    } catch (Exception e) {
        log.warn "Failed to write fedimpute_error.json: ${e.message}"
    }
}

// Classify INPUT_VALIDATION_VCF failures into structured error codes so the
// FedImpute UI can deep-link to a specific section of the workflow's docs
// site (https://afrigen-d.github.io/imputationserver2/errors). The validator
// (imputationserver-utils.jar) writes its message into validation_report.txt
// which the process cats to stdout — that text reaches us via
// workflow.errorMessage. Add a new (regex, code, anchor) tuple here when a
// new user-facing error gains a docs entry.
workflow.onError {
    def msg = (workflow.errorMessage ?: '').toString()

    if (msg =~ /(?i)contains more than one chromosome/) {
        emitStructuredError([
            code: 'MULTI_CHROMOSOME_VCF',
            severity: 'user_error',
            summary: 'VCF contains more than one chromosome — split by chromosome and resubmit.',
            docs_anchor: 'vcf-contains-more-than-one-chromosome',
        ])
    }
}

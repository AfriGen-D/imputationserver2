import groovy.json.JsonOutput

process QUALITY_CONTROL_VCF {
    
    label 'preprocessing'
    publishDir params.output, mode: 'copy', pattern: "qc_report.txt"
    publishDir params.output, mode: 'copy', pattern: "qc_output.txt"
    publishDir params.output, mode: 'copy', pattern: "chunks_summary.txt"
    publishDir params.output, mode: 'copy', pattern: "af_summary.txt"
    publishDir params.output, mode: 'copy', pattern: "${statisticsDir}/*.txt"

    input:
    path(vcf_files)
    path(site_files)
    path(chain_file)
    val(panel_version)

    output:
    path("${metaFilesDir}/*"), emit: chunks_csv, optional: true
    path("${chunksDir}/*"), emit: chunks_vcf
    path("${statisticsDir}/*"), optional: true
    path("maf.txt"), emit: maf_file, optional: true
    path("qc_report.txt"), emit: qc_report
    path("qc_output.txt"), emit: qc_output, optional: true
    path("chunks_summary.txt"), emit: chunks_summary, optional: true
    path("af_summary.txt"), emit: af_summary, optional: true

    script:
    chunksDir = 'chunks'
    metaFilesDir = 'metafiles'
    statisticsDir = 'statistics'
    mafFile = 'maf.txt'
    def chain = (!panel_version.equals(params.build)) ? "--chain ${chain_file}": ''
    def avail_mem = 1024
    if (!task.memory) {
        log.info '[QUALITY_CONTROL_VCF] Available memory not known - defaulting to 1GB. Specify process memory requirements to change this.'
    } else {
        avail_mem = (task.memory.mega*0.8).intValue()
    }

    """
    set +e
    echo '${JsonOutput.toJson(params.refpanel)}' > reference-panel.json

    # Verify if VCF files are valid
    for vcf in $vcf_files; do
        # Attempt to create the index using tabix
        if ! output=\$(tabix -p vcf "\$vcf" 2>&1); then
            echo ::group type=error
            echo "The provided VCF file is malformed."
            echo "Error: \$output"
            echo ::endgroup::
            exit 1
        fi
    done
    
    # TODO: create directories in java
    mkdir ${chunksDir}
    mkdir ${metaFilesDir}
    mkdir ${statisticsDir}
    echo ${chain_file}

    java -Xmx${avail_mem}M -jar /opt/imputationserver-utils/imputationserver-utils.jar \
        run-qc \
        --population ${params.population} \
        --reference reference-panel.json \
        --build ${params.build} \
        --maf-output ${mafFile} \
        --phasing-window ${params.phasing.window} \
        --chunksize ${params.chunksize} \
        --chunks-out ${chunksDir} \
        --statistics-out ${statisticsDir} \
        --metafiles-out ${metaFilesDir} \
        --report qc_report.txt \
        --no-index \
        $chain \
        $vcf_files > qc_output.txt 2>&1

    exit_code_a=\$?

    # Check if QC step failed
    if [[ \$exit_code_a -ne 0 ]]; then
        rm -rf ${metaFilesDir}
    fi

    # Emit chunks_summary.txt -- chunk counts aren't in qc_report.txt, but the
    # metafiles dir has one row per passing chunk and chunks-excluded.txt has
    # one row per excluded chunk. Surface these so downstream consumers (WES,
    # FedImpute) can show chunk-level QC status.
    chunks_passed=0
    chunks_excluded=0
    if [[ -d "${metaFilesDir}" ]]; then
        chunks_passed=\$(cat ${metaFilesDir}/* 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [[ -s chunks-excluded.txt ]]; then
        chunks_excluded=\$(wc -l < chunks-excluded.txt | tr -d ' ')
    fi
    chunks_total=\$((chunks_passed + chunks_excluded))
    {
        echo "Chunks total: \${chunks_total}"
        echo "Chunks passed QC: \${chunks_passed}"
        echo "Chunks excluded: \${chunks_excluded}"
    } > chunks_summary.txt

    # Emit af_summary.txt -- AF comparison stats from maf.txt (input AAF vs ref
    # panel AAF). CHISQ > 300 = the per-site AF discrepancy is statistically
    # improbable given sample size; common causes: genotyping errors, strand
    # misalignment, wrong-population reference panel. Empty if AF check is off
    # (params.allele_frequency_population == "off") since maf.txt is then absent.
    if [[ -s ${mafFile} ]]; then
        af_total=\$(tail -n +2 ${mafFile} | wc -l | tr -d ' ')
        af_mismatches=\$(awk 'NR>1 && \$10+0 > 300' ${mafFile} | wc -l | tr -d ' ')
        af_pct=\$(awk -v t="\${af_total}" -v m="\${af_mismatches}" 'BEGIN{printf "%.2f", (t>0 ? m/t*100 : 0)}')
        {
            echo "AF compared sites: \${af_total}"
            echo "AF mismatches (CHISQ>300): \${af_mismatches}"
            echo "AF mismatch rate: \${af_pct} %"
        } > af_summary.txt
    fi

    cat qc_report.txt
    cat qc_output.txt

    # Always exit 0 that QC files get published
    exit 0
    """

}

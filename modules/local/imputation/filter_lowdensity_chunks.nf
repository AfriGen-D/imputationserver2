process FILTER_LOWDENSITY_CHUNKS {

    label 'preprocessing'
    tag "${chunkfile}"

    input:
    tuple val(chr), val(start), val(end), val(phasing_status), path(chunkfile), path(m3vcf), path(sites), path(sites_tbi)
    val refpanel_build
    val minimac_min_ratio

    output:
    tuple val(chr), val(start), val(end), val(phasing_status), path(chunkfile), path(m3vcf), env(keep), emit: checked
    path("chunk-skipped-*.tsv"), optional: true, emit: skipped

    script:
    chr_cleaned = chr.startsWith('X.') ? 'X' : chr
    chr_mapped = (refpanel_build == 'hg38') ? 'chr' + chr_cleaned : chr_cleaned
    chunk_id = chunkfile.toString().replaceAll('.vcf.gz', '')

    // Pre-flight gate that mirrors minimac4's own `--min-ratio` check
    // (typed sites / imputed sites). minimac4 aborts the whole run with a
    // non-zero exit when a chunk falls below the ratio; that propagates to a
    // pipeline `terminate` and discards every other (successful) chunk. By
    // computing the same ratio here against the reference sites legend we can
    // drop only the offending chunk and let the rest of the run complete.
    // imputed = reference panel sites in the region (the legend, tabix-queried)
    // typed   = chunk variants that overlap those reference sites
    // Fail-safe: if the legend can't be read (missing index, tabix error), we
    // keep the chunk and let minimac4 be the authority -- we never block a
    // chunk we couldn't actually evaluate.
    //
    // DO NOT "fix" low-overlap regions by lowering --min-ratio or by merging a
    // sparse chunk with a denser neighbour. The ratio floor is also a
    // REFERENCE-PANEL DISCLOSURE CONTROL: with too few typed markers the output
    // is reconstructed almost entirely from the panel (not the target), so
    // emitting it would leak the panel's genotypes/haplotypes -- a real concern
    // for controlled-access panels (e.g. H3Africa). The control only works if
    // enforced PER REGION; a global relaxation, or aggregating a sparse region
    // with a dense one, launders a low-overlap region past the floor and
    // reopens the leak. If a skipped region's typed markers must be preserved,
    // the only privacy-safe route is to carry the user's OWN genotyped sites
    // through as TYPED rows at the merge step -- never to impute the gap.
    """
    tabix -f -p vcf ${chunkfile} 2>/dev/null || true

    region="${chr_mapped}:${start}-${end}"

    imputed=\$(tabix ${sites} \$region 2>/dev/null | wc -l | tr -d ' ')

    if [ -z "\$imputed" ] || [ "\$imputed" -eq 0 ]; then
        keep=true
    else
        typed=\$(comm -12 \\
            <(zcat ${chunkfile} | grep -v '^#' | awk '{print \$2}' | sort -u) \\
            <(tabix ${sites} \$region 2>/dev/null | awk '{print \$3}' | sort -u) \\
            | wc -l | tr -d ' ')

        keep=\$(awk -v t="\$typed" -v i="\$imputed" -v m="${minimac_min_ratio}" \\
            'BEGIN { r = (i > 0 ? t / i : 0); print (r >= m ? "true" : "false") }')

        if [ "\$keep" = "false" ]; then
            ratio=\$(awk -v t="\$typed" -v i="\$imputed" 'BEGIN { printf "%.4e", (i > 0 ? t / i : 0) }')
            printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \\
                "${chunk_id}" "${chr_mapped}" "${start}-${end}" "\$typed" "\$imputed" "\$ratio" \\
                > chunk-skipped-${chunk_id}.tsv
        fi
    fi
    """
}

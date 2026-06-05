include { MINIMAC4 } from '../modules/local/imputation/minimac4'
include { FILTER_LOWDENSITY_CHUNKS } from '../modules/local/imputation/filter_lowdensity_chunks'

workflow IMPUTATION {

    take:
    phased_ch

    main:
    if (params.refpanel.mapMinimac == null) {
        minimac_map = []
    } else {
        minimac_map = file(params.refpanel.mapMinimac, checkIfExists: true)
    }

    chromosomes = Channel.of(1..22, 'X.nonPAR', 'X.PAR1', 'X.PAR2', 'MT')
    minimac_m3vcf_ch = chromosomes
        .map {
            it ->
                def genotypes_file = file(PatternUtil.parse(params.refpanel.genotypes, [chr: it]))
                    if(!genotypes_file.exists()){
                        return null;
                    }
                return tuple(it.toString(),genotypes_file);
        }

    phased_m3vcf_ch = phased_ch.combine(minimac_m3vcf_ch, by: 0)

    // Drop chunks minimac4 would reject (typed/imputed < --min-ratio) before
    // they reach MINIMAC4, so one low-density chunk can't terminate the whole
    // run. Active only when the panel ships a sites legend and the feature is
    // not explicitly disabled; otherwise minimac4 stays the sole authority.
    // NB: use `sites_pattern` (the absolute, ${chr}-templated path), not
    // `sites` -- main.nf rewrites `refpanel.sites` to a staged relative
    // basename for input-staging, which would never resolve here.
    skip_lowdensity = params.refpanel.sites_pattern != null && params.imputation.skip_lowdensity_chunks != false

    if (skip_lowdensity) {
        // Separate chromosome source: `chromosomes` is a one-shot queue channel
        // already drained by minimac_m3vcf_ch above, so reusing it here would
        // yield an empty channel (and silently skip all imputation).
        minimac_sites_ch = Channel.of(1..22, 'X.nonPAR', 'X.PAR1', 'X.PAR2', 'MT')
            .map {
                it ->
                    def sites_path = PatternUtil.parse(params.refpanel.sites_pattern, [chr: it])
                    def sites_file = file(sites_path)
                    def sites_tbi  = file(sites_path + '.tbi')
                    if (!sites_file.exists() || !sites_tbi.exists()) {
                        return null;
                    }
                    return tuple(it.toString(), sites_file, sites_tbi);
            }

        checked_ch = phased_m3vcf_ch.combine(minimac_sites_ch, by: 0)

        FILTER_LOWDENSITY_CHUNKS(
            checked_ch,
            params.refpanel.build,
            params.imputation.minimac_min_ratio
        )

        FILTER_LOWDENSITY_CHUNKS.out.checked
            .branch {
                keep: it[6] == 'true'
                drop: true
            }
            .set { density_branched }

        density_branched.drop.subscribe { row ->
            log.warn "Skipping low-density chunk ${row[4]} (${row[0]}:${row[1]}-${row[2]}): typed/imputed below minimac4 --min-ratio (${params.imputation.minimac_min_ratio}); region will be absent from the result"
        }

        FILTER_LOWDENSITY_CHUNKS.out.skipped
            .collectFile(
                name: 'chunks-skipped-imputation.txt',
                storeDir: params.output,
                sort: true,
                seed: "CHUNK\tCHROM\tREGION\tTYPED\tIMPUTED\tRATIO\n"
            )

        minimac_in_ch = density_branched.keep.map { it[0..5] }
    } else {
        minimac_in_ch = phased_m3vcf_ch
    }

    MINIMAC4 (
        minimac_in_ch,
        minimac_map,
        params.refpanel.build,
        params.imputation.window,
        params.imputation.minimac_min_ratio,
        params.imputation.min_r2,
        params.imputation.decay,
        params.imputation.diff_threshold,
        params.imputation.prob_threshold,
        params.imputation.prob_threshold_s1,
        params.imputation.min_recom
    )

    emit:
    imputed_chunks = MINIMAC4.out.imputed_chunks
}

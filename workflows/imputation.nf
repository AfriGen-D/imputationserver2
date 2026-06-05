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
        // Resolve which chromosomes actually ship a tabix-indexed sites legend.
        // Built eagerly as a plain map (chr -> absolute legend path), not a
        // channel, so we can branch on membership without consuming a queue
        // channel twice.
        def chr_list = (1..22).collect { it.toString() } + ['X.nonPAR', 'X.PAR1', 'X.PAR2', 'MT']
        def sites_map = chr_list.collectEntries { c ->
            def sp = PatternUtil.parse(params.refpanel.sites_pattern, [chr: c])
            (file(sp).exists() && file(sp + '.tbi').exists()) ? [(c): sp] : [:]
        }

        // Chunks whose chromosome has a legend go through the density filter;
        // chunks without one (e.g. chrX PAR regions on panels that ship only a
        // single chrX legend, or any chr lacking a sites file) pass straight to
        // minimac4 -- never silently dropped just because we couldn't evaluate
        // them. minimac4 stays the authority for anything we can't pre-check.
        phased_m3vcf_ch
            .branch {
                has_sites: sites_map.containsKey(it[0])
                no_sites:  true
            }
            .set { by_sites }

        to_filter_ch = by_sites.has_sites.map { row ->
            def sp = sites_map[row[0]]
            tuple(row[0], row[1], row[2], row[3], row[4], row[5], file(sp), file(sp + '.tbi'))
        }

        FILTER_LOWDENSITY_CHUNKS(
            to_filter_ch,
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

        minimac_in_ch = density_branched.keep.map { it[0..5] }.mix(by_sites.no_sites)
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

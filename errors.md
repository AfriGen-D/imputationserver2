# Errors and Troubleshooting

This page documents the user-facing errors and warnings emitted by Imputation
Server 2 and explains how to resolve them. Each entry shows the literal message
text, when the pipeline raises it, the most common causes, and the steps to
recover.

If your error is not listed here, please contact the
[service administrator](contact.md) and include the job ID along with the full
log block surrounding the error.

---

## No chunks passed the QC step

### Message

```text
Remaining chunk(s): 0

Error: No chunks passed the QC step. Imputation cannot be started!
```

### Where it comes from

Emitted by the `QUALITY_CONTROL_VCF` Nextflow process
(`modules/local/quality_control/quality_control_vcf.nf`) after
`imputationserver-utils run-qc` has finished evaluating every chunk against the
selected reference panel. A chunk is dropped when it has fewer than the minimum
number of typed SNPs (default 10,000) overlapping the panel, or when it fails
allele or position checks.

### Common causes

1. **Build mismatch.** The input VCF is on a different genome assembly than the
   reference panel — for example uploading an `hg19` VCF against `v6hc-s-b38`,
   or running an `hg38` VCF against an `hg19` panel without a chain file.
2. **Wrong chromosome encoding.** The panel uses `chr1, chr2, ...` (UCSC) but
   the VCF uses `1, 2, ...` (Ensembl) or vice versa. After lift-over the
   contigs no longer overlap, so every chunk is empty.
3. **Population/panel mismatch.** Selecting a population that does not exist on
   the panel (for example, choosing a non-African population on the AFR-only
   subset of v6hc-s) excludes most variants during the allele-frequency check
   and leaves no chunks.
4. **Too few typed sites.** Sparse genotyping data (very small chip, heavy
   pre-filtering, or a single small region) does not contain enough variants
   per 20 Mb chunk to clear the 10,000-SNP threshold.
5. **Strand or allele issues.** A high allele-mismatch or strand-flip rate
   relative to the panel exhausts the chunk's usable variants.

### How to fix

1. Confirm the VCF build matches the panel build:

    ```bash
    bcftools view -h input.vcf.gz | grep -E '^##(reference|contig)' | head
    ```

    For panels published on `hg38` (V6HC-S, V6HC-S_AFR, V7HC-S, 1KG NYGC 30x)
    the input must also be `hg38`, or you must enable lift-over by selecting
    the corresponding `hg19 → hg38` chain file at job submission.

2. Normalise chromosome names if needed:

    ```bash
    bcftools annotate --rename-chrs chr_map.txt input.vcf.gz \
        -Oz -o renamed.vcf.gz
    ```

3. Pick a population that the panel actually publishes. Each panel's
   `cloudgene.yaml` declares supported populations; if none of them describe
   your cohort, select the `Off` (skip allele-frequency check) option instead
   of forcing an unrelated code.

4. Inspect `qc_report.txt` and the `statistics/` directory in the job output.
   The `chunks-excluded.txt` file lists the rejection reason for every chunk —
   that is the fastest way to discover whether the problem is per-chunk SNP
   counts, allele mismatches, or strand flips.

5. Re-run with `mode = qc-only` to iterate quickly without paying the
   imputation cost.

---

## Chunks excluded for too few SNPs

### Message

```text
Warning: N Chunk(s) excluded: < 10000 SNPs (see chunks-excluded.txt for details).
```

### Trigger

Each 20 Mb chunk is required to contain at least 10,000 typed sites that match
the reference panel. Chunks below that threshold are dropped from imputation.

### How to handle

This is a warning when *some* chunks are excluded but the job still has work to
do. It becomes the [No chunks passed the QC step](#no-chunks-passed-the-qc-step) error when
*every* chunk is excluded. If only a small fraction of chunks are dropped you
can usually proceed; the excluded regions will simply have no imputed output.
Inspect `chunks-excluded.txt` to confirm which regions are missing before using
the results downstream.

---

## Malformed VCF file

### Message

```text
The provided VCF file is malformed.
Error: <tabix output>
```

### Trigger

Both `INPUT_VALIDATION_VCF` and `QUALITY_CONTROL_VCF` invoke
`tabix -p vcf <file>` to build an index before processing. A non-zero exit code
from `tabix` aborts the job with this message and prints the tool's stderr
under `Error:`.

### Common causes

- The file is bgzipped incorrectly (`gzip` instead of `bgzip`).
- Records are not sorted by chromosome then position.
- The header is missing required `##contig` lines.
- The upload was truncated mid-transfer.

### How to fix

```bash
# Re-bgzip and re-sort
bcftools sort input.vcf.gz -Oz -o sorted.vcf.gz
tabix -p vcf sorted.vcf.gz   # must succeed before re-uploading
```

If `tabix` still fails, run `bcftools view -h sorted.vcf.gz` to confirm the
header is valid, and re-upload only after `tabix` exits cleanly.

---

## No VCF input files detected

### Message

```text
::error:: No vcf.gz input files detected.
```

### Trigger

`main.nf` aborts before any process runs when the `files` parameter expands to
zero matches.

### How to fix

- Verify the upload completed and the files end in `.vcf.gz`.
- When running locally, check the glob in `params.files` against your actual
  file layout — quote it so the shell does not expand it before Nextflow sees
  it.

---

## Invalid phasing engine

### Message

```text
::error:: For phasing, only options 'eagle', 'beagle' or 'no_phasing' are allowed.
```

### Trigger

`main.nf` validates `params.phasing.engine` at startup. Any value other than
`eagle`, `beagle`, or `no_phasing` halts the run.

### How to fix

Set the parameter to one of the three accepted values in your `job.config` or
on the command line:

```groovy
params {
    phasing.engine = 'eagle'
}
```

---

## Sample-count out of range

### Message

```text
The number of samples is below the required minimum (<min>).
```

or

```text
The number of samples exceeds the maximum allowed (<max>).
```

### Trigger

`imputationserver-utils validate` is invoked by `INPUT_VALIDATION_VCF` with
`--minSamples ${params.min_samples}` and `--maxSamples ${params.max_samples}`
(defaults: 20 and 50,000). Cohorts outside that window are rejected.

### How to fix

- For small cohorts (under 20), either pad the file with additional
  individuals or contact the service administrator to request a lowered
  threshold for your project.
- For very large cohorts, split the file by sample (e.g. with
  `bcftools view -S samples_part_N.txt`) and submit each part as a separate
  job.

---

## Imputation job failed

### Message

```text
::error:: Imputation job <statusMessage>.
```

### Trigger

A non-success status returned by the `IMPUTATION` workflow surfaces in
`main.nf` (line 165). The exact `<statusMessage>` is forwarded from the
underlying imputation tool (Minimac4 or Beagle).

### How to fix

The status message is the diagnostic. The most common variants:

- `cancelled` — the job was cancelled by the user or by the queue.
- `failed (out of memory)` — re-run with a larger executor profile.
- `failed (segmentation fault)` — usually a corrupt chunk; re-upload after
  re-validating with `bcftools sort | tabix`.

Inspect `.nextflow.log` in the work directory for the failing process and its
exit code, then forward the bottom 200 lines to the service administrator if
the cause is not obvious.

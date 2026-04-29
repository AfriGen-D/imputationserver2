---
layout: home

hero:
  name: "Imputation Server 2"
  text: "Genotype Imputation Pipeline"
  tagline: "AfriGen-D fork of the Nextflow workflow that powers impute.afrigen-d.org. Run the African reference panels (V6HC-S, V6HC-S_AFR, V7HC-S, 1KG NYGC 30x) locally, on SLURM, on AWS Batch, or behind Cloudgene."
  image:
    src: /afrigen-d-logo.png
    alt: AfriGen-D
  actions:
    - theme: brand
      text: Quick Start
      link: '#run-with-test-data'
    - theme: alt
      text: Errors and Troubleshooting
      link: /errors
    - theme: alt
      text: View on GitHub
      link: https://github.com/AfriGen-D/imputationserver2

features:
  - icon: 🧬
    title: Reference panels for African cohorts
    details: >-
      H3Africa V6HC-S, V6HC-S_AFR, V7HC-S, and 1KG NYGC 30x reference panels --
      all hg38, all hosted on the ILIFU research cloud, all served by the
      AfriGen-D imputation service.
  - icon: ⚙️
    title: Nextflow + Cloudgene
    details: >-
      Runs as a Nextflow DSL2 pipeline directly, or as an installable
      Cloudgene application with a UI. Supports local, SLURM, and AWS Batch
      executors out of the box.
    link: '#run-with-cloudgene'
    linkText: Cloudgene setup
  - icon: 🛠️
    title: Errors and remediation documented
    details: >-
      Every user-visible error from QC, validation, and imputation has a
      dedicated entry with the literal message, the trigger, common causes,
      and concrete fix steps.
    link: /errors
    linkText: Browse error reference
---

[![imputationserver2](https://github.com/genepi/imputationserver2/actions/workflows/ci-tests.yml/badge.svg)](https://github.com/genepi/imputationserver2/actions/workflows/ci-tests.yml)
[![nf-test](https://img.shields.io/badge/tested_with-nf--test-337ab7.svg)](https://github.com/askimed/nf-test)

This repository hosts the AfriGen-D fork of the Imputation Server 2 Nextflow
workflow. Upstream development continues at
[`genepi/imputationserver2`](https://github.com/genepi/imputationserver2);
this fork carries African-cohort-specific configuration, panel integrations,
and documentation.

## Run with test data

The pipeline ships with small test data so you can verify your installation
end to end:

```bash
nextflow run main.nf -c conf/test_single_vcf.config
```

## Run with custom configuration

Create a `job.config`:

```groovy
params {
    project                     = "my-test-project"
    build                       = "hg38"
    files                       = "tests/data/input/three/*.vcf.gz"
    allele_frequency_population = "afr"
    mode                        = "imputation"
    refpanel_yaml               = "tests/hapmap-2/2.0.0/imputation-hapmap2.yaml"
    output                      = "output"
}
```

Run the pipeline with that configuration:

```bash
nextflow run main.nf -c job.config
```

## Parameters

| Parameter             | Default Value         | Description                                        |
| --------------------- | --------------------- | -------------------------------------------------- |
| `project`             | `null`                | Project name                                       |
| `project_date`        | `date`                | Project date                                       |
| `files`               | `null`                | List of input files                                |
| `allele_frequency_population` | `null`        | Allele Frequency Population information            |
| `refpanel_yaml`       | `null`                | Reference panel YAML file                          |
| `mode`                | `imputation`          | Processing mode (`imputation` or `qc-only`)        |
| `chunksize`           | `20000000`            | Chunk size for processing                          |
| `min_samples`         | `20`                  | Minimum number of samples needed                   |
| `max_samples`         | `50000`               | Maximum number of samples allowed                  |
| `merge_samples`       | `true`                | Execute compression and encryption workflow        |
| `password`            | `null`                | Password for encryption                            |
| `send_mail`           | `false`               | Enable or disable email notifications              |
| `service.name`        | `Imputation Server 2` | Service name                                       |
| `service.email`       | `null`                | Service email                                      |
| `service.url`         | `null`                | Service URL                                        |
| `user.name`           | `null`                | User's name                                        |
| `user.email`          | `null`                | User's email                                       |
| `phasing.engine`      | `eagle`               | Phasing method (`eagle`, `beagle`, or `no_phasing`)|
| `phasing.window`      | `5000000`             | Phasing window size                                |
| `imputation.enabled`  | `true`                | Enable or disable imputation                       |
| `imputation.window`   | `500000`              | Imputation window size                             |
| `imputation.minimac_min_ratio` | `0.00001`    | Minimac minimum ratio                              |
| `imputation.min_r2`   | `0`                   | R2 filter value                                    |
| `imputation.meta`     | `false`               | Enable or disable empirical output creation        |
| `imputation.md5`      | `false`               | Enable or disable md5 sum creation for results     |
| `imputation.create_index` | `false`           | Enable or disable index creation for imputed files |
| `imputation.decay`    | `0`                   | Set minimac decay                                  |
| `encryption.enabled`  | `true`                | Enable or disable encryption                       |
| `encryption.aes`      | `false`               | Enable or disable AES method for encryption        |
| `ancestry.enabled`    | `false`               | Enable or disable ancestry analysis                |
| `ancestry.dim`        | `10`                  | Ancestry analysis dimension                        |
| `ancestry.dim_high`   | `20`                  | High dimension for ancestry analysis               |
| `ancestry.batch_size` | `50`                  | Batch size for ancestry analysis                   |
| `ancestry.reference`  | `null`                | Ancestry reference data                            |
| `ancestry.max_pcs`    | `8`                   | Maximum principal components for ancestry          |
| `ancestry.k`          | `10`                  | K value for ancestry analysis                      |
| `ancestry.threshold`  | `0.75`                | Ancestry threshold                                 |

## Reference panel configuration

Reference panels are described by a YAML file consumed by Cloudgene and the
pipeline. Each panel declares its build, file locations, and the populations
it supports.

### YAML structure

| Field         | Description                                                                     |
| ------------- | ------------------------------------------------------------------------------- |
| `name`        | The name of the reference panel.                                                |
| `description` | A brief description of the reference panel.                                     |
| `version`     | The version of the reference panel.                                             |
| `website`     | The website where more information about the panel can be found.                |
| `category`    | The category to which the reference panel belongs (must be `RefPanel`).         |
| `properties`  | A section containing specific properties of the reference panel.                |

#### Properties

| Property      | Description                                                                 | Required |
| ------------- | --------------------------------------------------------------------------- | -------- |
| `id`          | An identifier for the reference panel.                                      | yes      |
| `genotypes`   | The location of the genotype files for the reference panel data.            | yes      |
| `sites`       | The location of the site files for the reference panel data.                | yes      |
| `mapEagle`    | The location of the genetic map file used for phasing with eagle.           | yes      |
| `refEagle`    | The location of the BCF file for the reference panel data for eagle.        | yes      |
| `mapBeagle`   | The location of the genetic map file used for phasing with Beagle.          | no       |
| `refBeagle`   | The location of the BCF file for the reference panel data for Beagle.       | no       |
| `build`       | The genome build version used for the reference panel (`hg19` or `hg38`).   | yes      |
| `range`       | A range that is used for imputation (e.g. HLA).                             | no       |
| `mapMinimac`  | The location of the map file for Minimac.                                   | no       |
| `populations` | A dictionary mapping population identifiers to their names.                 | yes      |
| `qcFilter`    | A dictionary mapping quality filters to their values.                       | no       |

##### Populations

| Identifier | Name                                     |
| ---------- | ---------------------------------------- |
| `id`       | The id of the population (e.g. `afr`).   |
| `name`     | The label of the population (e.g. `AFR`).|
| `samples`  | Number of samples in the reference panel.|

The population id must match the value used in the legend files.

#### Quality filters

| Filter               | Name                                                  | Default |
| -------------------- | ----------------------------------------------------- | ------- |
| `overlap`            | Minimal overlap between gwas data and reference panel | 0.5     |
| `minSnps`            | Minimal #SNPs per chunk                               | 3       |
| `sampleCallrate`     | Minimal sample call rate                              | 0.5     |
| `mixedGenotypeschrX` | -                                                     | 0.1     |
| `strandFlips`        | Maximal allowed strand flips                          | 100     |

### Example YAML

```yaml
name: HapMap 2
description: HapMap2 Reference Panel for Imputation Server
version: 2.0.0
website: http://imputationserver.sph.umich.edu
category: RefPanel

properties:
  id: hapmap2
  genotypes: s3://cloudgene/refpanels/hapmap/m3vcfs/hapmap_r22.chr$chr.CEU.hg19.recode.m3vcf.gz
  legend: s3://cloudgene/refpanels/hapmap/legends/hapmap_r22.chr$chr.CEU.hg19_impute.legend.gz
  mapEagle: s3://cloudgene/refpanels/hapmap/map/genetic_map_hg19_withX.txt.gz
  refEagle: s3://cloudgene/refpanels/hapmap/bcfs/hapmap_r22.chr$chr.CEU.hg19.recode.bcf
  build: hg19
  populations:
    - id: eur
      name: EUR
      samples: 60
    - id: off
      name: Off
      samples: -1
```

The `$chr` placeholder is substituted with the chromosome number by the
pipeline at runtime.

A legend file is a tab-delimited file with five columns: `id`, `position`,
`a0`, `a1`, `all.aaf`.

## Run with Cloudgene

### Requirements

- Nextflow
- Docker or Singularity
- Java 14 or newer

### Installation

```bash
# Install Cloudgene 3
curl -s install.cloudgene.io | bash -s 3.0.0-rc3

# Install the imputationserver2 app
./cloudgene install imputationserver2@latest

# Install a reference panel (HapMap 2 example)
./cloudgene install https://genepi.i-med.ac.at/downloads/imputation/imputation-hapmap2.zip

# Start the server
./cloudgene server
```

Open [http://localhost:8082](http://localhost:8082) and log in with the default
admin account (`admin` / `admin1978`). A small public test VCF for end-to-end
validation lives at
[`tests/data/input/chr20-phased/chr20.R50.merged.1.330k.recode.small.vcf.gz`](https://github.com/genepi/imputationserver2/raw/main/tests/data/input/chr20-phased/chr20.R50.merged.1.330k.recode.small.vcf.gz).

### Default configuration

The default configuration uses Docker and Nextflow's
[local executor](https://www.nextflow.io/docs/latest/executor.html#local).

### Running on SLURM

Configure via the web interface (Applications → imputationserver2 → Settings)
or edit `apps/imputationserver/nextflow.config`:

```groovy
process {
  executor = 'slurm'
  queue    = 'QueueName'
}

errorStrategy = { task.exitStatus == 143 ? 'retry' : 'terminate' }
maxErrors  = '-1'
maxRetries = 3
```

See [Nextflow's SLURM documentation](https://www.nextflow.io/docs/latest/executor.html#slurm)
for additional options.

### Running on AWS Batch

1. Create the AWS Batch queue and IAM role
   ([Nextflow guide](https://www.nextflow.io/docs/latest/aws.html#aws-batch)).
2. Configure via Settings or `apps/imputationserver/nextflow.config`:

   ```groovy
   aws {
     region = 'eu-central-1'
     client { uploadChunkSize = 10485760 }
     batch  {
       cliPath       = '/home/ec2-user/miniconda/bin/aws'
       executionRole = 'arn:aws:iam::***'
     }
   }

   process {
     executor = 'awsbatch'
     queue    = 'QueueName'
     scratch  = false
   }
   ```

3. In Settings → General set the workspace to `S3://<bucket>/<subfolder>`.

Optionally enable [Wave](https://www.nextflow.io/docs/latest/wave.html) and
[Fusion](https://www.nextflow.io/docs/latest/fusion.html):

```groovy
wave   { enabled = true; endpoint = 'https://wave.seqera.io' }
fusion { enabled = true }
```

### Mail support

- Configure the mail server in Settings → General → Mail.
- Add the following to `config/nextflow.config` so Nextflow inherits
  Cloudgene's mail settings (see
  [Nextflow mail config](https://www.nextflow.io/docs/latest/config.html#config-mail)):

  ```groovy
  mail {
    smtp.host           = "${CLOUDGENE_SMTP_HOST}"
    smtp.port           = "${CLOUDGENE_SMTP_PORT}"
    smtp.user           = "${CLOUDGENE_SMTP_USER}"
    smtp.password       = "${CLOUDGENE_SMTP_PASSWORD}"
    smtp.auth           = true
    smtp.starttls.enable = true
    smtp.ssl.protocols  = 'TLSv1.2'
  }
  ```

- Set `params.config.send_mail = true` in the application configuration to
  enable mail notifications from the pipeline.

### Adapting default parameters

Parameters can be overridden in the application's `nextflow.config`:

```groovy
params.chunksize         = 500000
params.imputation.window = 100000
```

## Development

Build the docker image locally:

```bash
docker build -t genepi/imputation-docker:latest .
```

Run the test suite:

```bash
nf-test test
```

## License

`imputationserver2` is MIT licensed and was originally developed at the
[Institute of Genetic Epidemiology](https://genepi.i-med.ac.at/), Medical
University of Innsbruck. The AfriGen-D fork carries African-specific
configuration and is maintained by the
[AfriGen-D consortium](https://afrigen-d.org).

For people, see the [contact page](/contact).

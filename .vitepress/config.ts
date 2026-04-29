import { defineConfig } from 'vitepress'
import { withMermaid } from 'vitepress-plugin-mermaid'
import taskLists from 'markdown-it-task-lists'

export default withMermaid(defineConfig({
  title: 'Imputation Server 2',
  description:
    'AfriGen-D fork of the Imputation Server 2 Nextflow pipeline -- ' +
    'reference panels, parameters, and troubleshooting for the African ' +
    'genotype imputation service.',
  base: '/imputationserver2/',
  lang: 'en-US',
  cleanUrls: true,
  lastUpdated: true,
  ignoreDeadLinks: 'localhostLinks',
  srcExclude: ['README.md', 'CLAUDE.md'],

  head: [
    ['link', { rel: 'icon', href: '/imputationserver2/afrigen-d-logo.png' }],
    ['meta', { name: 'theme-color', content: '#C94234' }],
  ],

  themeConfig: {
    logo: '/afrigen-d-logo.png',
    siteTitle: 'Imputation Server 2',

    outline: [2, 3],
    outlineTitle: 'On this page',

    nav: [
      { text: 'Home', link: '/' },
      { text: 'Errors', link: '/errors' },
      { text: 'Contact', link: '/contact' },
      {
        text: 'AfriGen-D',
        items: [
          { text: 'Imputation Service', link: 'https://impute.afrigen-d.org' },
          { text: 'Service Docs', link: 'https://afrigen-d.github.io/imputation-service-docs/' },
          { text: 'Initiative', link: 'https://afrigen-d.org' },
        ],
      },
    ],

    sidebar: [
      {
        text: 'Pipeline',
        items: [
          { text: 'Overview', link: '/' },
          { text: 'Errors and Troubleshooting', link: '/errors' },
          { text: 'Contact', link: '/contact' },
        ],
      },
    ],

    socialLinks: [
      {
        icon: 'github',
        link: 'https://github.com/AfriGen-D/imputationserver2',
      },
    ],

    footer: {
      message:
        'Released under the MIT License. ' +
        'Part of the AfriGen-D Initiative.',
      copyright: 'Copyright &copy; 2026 AfriGen-D Project',
    },

    search: {
      provider: 'local',
    },

    editLink: {
      pattern:
        'https://github.com/AfriGen-D/imputationserver2/edit/main/:path',
      text: 'Edit this page on GitHub',
    },

    lastUpdated: {
      text: 'Last updated',
      formatOptions: { dateStyle: 'medium' },
    },
  },

  markdown: {
    theme: { light: 'github-light', dark: 'github-dark' },
    config: (md) => {
      md.use(taskLists, { enabled: true, label: true })
    },
  },
}))

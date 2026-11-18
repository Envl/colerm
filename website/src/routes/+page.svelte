<script lang="ts">
  import { dev } from '$app/environment'
  import { onMount } from 'svelte'
  import TerminalPane from '$lib/TerminalPane.svelte'

  type Pane = {
    id: string
    repo: string
    path: string
    cwd: string
    branch: string
    gitState: string
    diff: string
    accent: string
    intro: string[]
    files: Record<string, string>
    startupCommands?: string[]
  }

  const FIRST_PANE_ID = 'colerm'
  const pageTitle = 'Colerm — Terminal columns for macOS'
  const pageDescription = 'Run Ghostty terminals side by side on macOS, review Git diffs, and track coding agent status from your tabs.'

  function ansiLink(url: string, color: number) {
    return `\x1b[38;5;${color}m${url}\x1b[0m\n`
  }

  let panes = $state<Pane[]>([
    {
      id: FIRST_PANE_ID,
      repo: 'colerm',
      path: '~/Code/colerm',
      cwd: '/home/colerm',
      branch: 'main',
      gitState: '2 changes',
      diff: '+12 −4',
      accent: '#78dcca',
      intro: [
        '\x1b[38;5;245mLast login: Wed Aug 5 09:42:18 on ttys056\x1b[0m',
        '',
        '\x1b[38;5;114m$ git status --short\x1b[0m',
        ' M README.md',
        ' M Package.swift',
        '',
        '\x1b[38;5;114m$ swift build\x1b[0m',
        'Building for debugging…',
        '\x1b[38;5;114mBuild complete!\x1b[0m (2.41s)',
      ],
      files: {
        '/home/colerm/README.md':
          '# Colerm\n\nA native macOS terminal workspace powered by Ghostty.\n',
        '/home/colerm/Package.swift':
          '// swift-tools-version: 6.0\nlet package = Package(name: "Colerm")\n',
        '/home/colerm/Sources/ColermApp/main.swift':
          'import AppKit\n\nfinal class ColermApp {}\n',
      },
    },
    {
      id: 'shell-click',
      repo: 'shell-click',
      path: '~/Code/shell-click',
      cwd: '/home/shell-click',
      branch: 'main',
      gitState: 'clean',
      diff: '+1 −0',
      accent: '#78dcca',
      startupCommands: ['ls', 'cat shellclick.dev.url'],
      intro: [
        '\x1b[38;5;245mShell Click product workspace\x1b[0m',
        '',
        '\x1b[38;5;114mOne-click commands for macOS.\x1b[0m',
      ],
      files: {
        '/home/shell-click/README.md':
          '# Shell Click\n\nRun and manage project commands on macOS.\n',
        '/home/shell-click/package.json':
          '{\n  "name": "shell-click",\n  "private": true\n}\n',
        '/home/shell-click/shellclick.dev.url':
          ansiLink('https://shellclick.dev', 79),
      },
    },
    {
      id: 'pinchkey',
      repo: 'pinchkey',
      path: '~/Code/pinchkey',
      cwd: '/home/pinchkey',
      branch: 'release/1.0.38',
      gitState: 'clean',
      diff: '0 changes',
      accent: '#c4a7ff',
      startupCommands: ['ls', 'cat pinchkey.lumik.space.url'],
      intro: [
        '\x1b[38;5;245mPinchKey product workspace\x1b[0m',
        '',
        '\x1b[38;5;183mThe keyboard-first app switcher for macOS.\x1b[0m',
      ],
      files: {
        '/home/pinchkey/README.md':
          '# PinchKey\n\nJump between windows and apps with the keyboard.\n',
        '/home/pinchkey/PinchKey.app/Contents/Info.plist':
          '<?xml version="1.0"?>\n<plist version="1.0" />\n',
        '/home/pinchkey/pinchkey.lumik.space.url':
          ansiLink('https://pinchkey.lumik.space', 183),
      },
    },
    {
      id: 'knowto',
      repo: 'knowto',
      path: '~/Code/knowto',
      cwd: '/home/knowto',
      branch: 'main',
      gitState: 'clean',
      diff: '+8 −1',
      accent: '#74bdf8',
      intro: [
        '\x1b[38;5;245mKnowledge workspace\x1b[0m',
        '',
        '\x1b[38;5;117m$ bun run dev\x1b[0m',
        'Starting TanStack Start…',
        'Hono API ready on http://localhost:5888',
        'MCP endpoint: http://localhost:5888/mcp',
        '',
        '\x1b[38;5;114m✓ connected to local D1\x1b[0m',
        '✓ auth provider ready',
      ],
      files: {
        '/home/knowto/README.md':
          '# KnowTo\n\nLocal-first knowledge capture with a small, fast API.\n',
        '/home/knowto/package.json':
          '{\n  "name": "knowto",\n  "scripts": { "dev": "vinxi dev" }\n}\n',
        '/home/knowto/src/routes/index.tsx':
          'export default function Home() { return <main /> }\n',
      },
    },
    {
      id: 'pulsebar',
      repo: 'pulsebar',
      path: '~/Code/pulsebar',
      cwd: '/home/pulsebar',
      branch: 'polish-menu',
      gitState: '1 change',
      diff: '+42 −6',
      accent: '#f89ab4',
      startupCommands: ['ls', 'cat pulsebar.lumik.space.url'],
      intro: [
        '\x1b[38;5;245mPulsebar product workspace\x1b[0m',
        '',
        '\x1b[38;5;211mA quiet menu bar for the things worth keeping close.\x1b[0m',
      ],
      files: {
        '/home/pulsebar/README.md':
          '# Pulsebar\n\nA quiet menu bar for the things worth keeping close.\n',
        '/home/pulsebar/Pulsebar.app/Contents/Info.plist':
          '<?xml version="1.0"?>\n<plist version="1.0" />\n',
        '/home/pulsebar/pulsebar.lumik.space.url':
          ansiLink('https://pulsebar.lumik.space', 211),
      },
    },
    {
      id: 'web',
      repo: 'web',
      path: '~/Code/web',
      cwd: '/home/web',
      branch: 'site/refresh',
      gitState: '4 changes',
      diff: '+76 −12',
      accent: '#70d6c3',
      intro: [
        '\x1b[38;5;245mProduct site workspace\x1b[0m',
        '',
        '\x1b[38;5;80m$ pnpm check\x1b[0m',
        'svelte-check found 0 errors and 0 warnings',
        '',
        '\x1b[38;5;80m$ pnpm build\x1b[0m',
        'vite v8.0.4 building for production…',
        '\x1b[38;5;114m✓ built in 1.14s\x1b[0m',
      ],
      files: {
        '/home/web/README.md':
          '# Product site\n\nThe quiet, clear front door for the product.\n',
        '/home/web/package.json':
          '{\n  "name": "product-site",\n  "scripts": { "build": "vite build" }\n}\n',
        '/home/web/src/routes/+page.svelte':
          '<main>Product site</main>\n',
      },
    },
    {
      id: 'tools',
      repo: 'tools',
      path: '~/Code/tools',
      cwd: '/home/tools',
      branch: 'main',
      gitState: 'clean',
      diff: '+2 −0',
      accent: '#f0bd70',
      intro: [
        '\x1b[38;5;245mTools workspace\x1b[0m',
        '',
        '\x1b[38;5;220m$ git status\x1b[0m',
        'On branch main',
        'Your branch is up to date with \'origin/main\'.',
        'nothing to commit, working tree clean',
        '',
        '\x1b[38;5;114mReady.\x1b[0m',
      ],
      files: {
        '/home/tools/README.md':
          '# Tools\n\nSmall, dependable utilities for the rest of the workspace.\n',
        '/home/tools/package.json':
          '{\n  "name": "workspace-tools",\n  "private": true\n}\n',
        '/home/tools/scripts/doctor.sh':
          '#!/bin/sh\nprintf "workspace healthy\\n"\n',
      },
    },
  ])

  let activePane = $state(FIRST_PANE_ID)

  function addPane() {
    const sessionNumber = panes.length + 1
    const pane: Pane = {
      id: `session-${sessionNumber}`,
      repo: `session-${sessionNumber}`,
      path: `~/Code/session-${sessionNumber}`,
      cwd: `/home/session-${sessionNumber}`,
      branch: 'new-session',
      gitState: 'new',
      diff: '0 changes',
      accent: ['#78dcca', '#d2a8ff', '#f0bd70', '#74bdf8'][sessionNumber % 4],
      intro: [
        '\x1b[38;5;245mNew terminal session\x1b[0m',
        '',
        `\x1b[38;5;114m$ cd ~/Code/session-${sessionNumber}\x1b[0m`,
        'Working directory ready.',
        '',
        '\x1b[38;5;114mType a command to begin.\x1b[0m',
      ],
      files: {
        [`/home/session-${sessionNumber}/README.md`]:
          `# Session ${sessionNumber}\n\nA fresh Colerm terminal session.\n`,
      },
    }

    panes.push(pane)
    selectPane(pane.id)
  }

  function closePane(id: string) {
    if (panes.length === 1) return

    const closingIndex = panes.findIndex(pane => pane.id === id)
    const nextPane = panes[closingIndex + 1] ?? panes[closingIndex - 1]
    panes = panes.filter(pane => pane.id !== id)

    if (activePane === id && nextPane) {
      selectPane(nextPane.id)
    }
  }

  function selectPane(id: string) {
    activePane = id
    requestAnimationFrame(() => {
      document.getElementById(`tab-${id}`)?.scrollIntoView({
        behavior: 'smooth',
        block: 'nearest',
        inline: 'center',
      })
      document.getElementById(`terminal-${id}`)?.scrollIntoView({
        behavior: 'smooth',
        block: 'nearest',
        inline: 'center',
      })
    })
  }

  onMount(() => {
    requestAnimationFrame(() => selectPane(FIRST_PANE_ID))
  })
</script>

<svelte:head>
  <title>{dev ? '🟠 ' : ''}{pageTitle}</title>
  <meta name="theme-color" content="#090909" />
  <meta name="description" content={pageDescription} />
  <meta name="author" content="Colerm" />
  <meta name="robots" content="index, follow" />
  <link rel="canonical" href="https://colerm.com/" />
  <link rel="icon" type="image/png" href="/colerm-logo-1024.png" />
  <link rel="apple-touch-icon" href="/colerm-logo-1024.png" />
  <meta property="og:locale" content="en_US" />
  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Colerm" />
  <meta property="og:title" content={pageTitle} />
  <meta property="og:description" content={pageDescription} />
  <meta property="og:url" content="https://colerm.com/" />
  <meta property="og:image" content="https://colerm.com/og.png" />
  <meta property="og:image:alt" content="Colerm terminal workspace" />
  <meta property="og:image:type" content="image/png" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content={pageTitle} />
  <meta name="twitter:description" content={pageDescription} />
  <meta name="twitter:image" content="https://colerm.com/og.png" />
  <meta name="twitter:image:alt" content="Colerm terminal workspace" />
  <script type="application/ld+json">
    {
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      "name": "Colerm",
      "url": "https://colerm.com/",
      "description": "A native macOS terminal workspace powered by Ghostty, with resizable columns, Git diffs, and coding agent status in tabs.",
      "applicationCategory": "DeveloperApplication",
      "operatingSystem": "macOS 14 or later",
      "image": "https://colerm.com/og.png",
      "codeRepository": "https://github.com/Envl/colerm"
    }
  </script>
</svelte:head>

<div class="site-shell">
  <header class="site-header">
    <a class="wordmark" href="/" aria-label="Colerm home">
      <img class="wordmark-logo" src="/colerm-logo-1024.png" alt="" aria-hidden="true" />
      <span>Colerm</span>
    </a>

    <div class="header-links">
      <a
        class="support-link"
        href="https://buymeacoffee.com/envl"
        target="_blank"
        rel="noreferrer"
        aria-label="Buy me a coffee"
      >Buy me a coffee ↗</a>
      <a
        class="support-link"
        href="https://x.com/sesampicr"
        target="_blank"
        rel="noreferrer"
        aria-label="Colerm on X"
      >X ↗</a>
      <a
        class="github-link"
        href="https://github.com/Envl/colerm"
        target="_blank"
        rel="noreferrer"
        aria-label="Colerm on GitHub"
        title="Colerm on GitHub"
      >
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="M12 .5a12 12 0 0 0-3.79 23.39c.6.11.82-.26.82-.58v-2.04c-3.34.73-4.04-1.61-4.04-1.61-.55-1.39-1.34-1.76-1.34-1.76-1.09-.75.08-.74.08-.74 1.2.08 1.84 1.23 1.84 1.23 1.07 1.84 2.8 1.31 3.49 1 .11-.78.42-1.31.76-1.61-2.67-.3-5.47-1.34-5.47-5.93 0-1.31.47-2.38 1.24-3.22-.12-.3-.54-1.52.12-3.17 0 0 1.01-.32 3.3 1.23a11.5 11.5 0 0 1 6 0c2.29-1.55 3.3-1.23 3.3-1.23.66 1.65.24 2.87.12 3.17.77.84 1.24 1.91 1.24 3.22 0 4.6-2.8 5.62-5.48 5.92.43.37.81 1.1.81 2.22v3.29c0 .32.22.7.83.58A12 12 0 0 0 12 .5Z" />
        </svg>
        <span>GitHub</span>
      </a>
    </div>
  </header>

  <main>
    <section class="hero" aria-labelledby="hero-title">
      <h1 id="hero-title">Terminal columns <em>for macOS.</em></h1>
      <p class="hero-copy">
        Run Ghostty terminals side by side, review Git diffs, and see which coding agents need your attention. Requires macOS 14 or later.
      </p>
      <a class="download-link" href="https://github.com/Envl/colerm/releases/latest/download/Colerm.dmg" rel="external" aria-label="Download Colerm for macOS">
        Download for macOS <span>↓</span>
      </a>
    </section>

    <section class="demo-wrap" id="demo" aria-labelledby="demo-title">
      <div class="demo-intro">
        <h2 id="demo-title">Browser demo</h2>
        <p class="demo-note">Select a terminal and run commands against sample files.</p>
      </div>

      <div class="app-window">
        <div class="window-chrome">
          <div class="traffic-lights" aria-hidden="true">
            <span class="close"></span><span class="minimize"></span><span class="maximize"></span>
          </div>
          <strong>Colerm</strong>
        </div>

        <div class="workspace-tabs" role="tablist" aria-label="Open terminal sessions">
          {#each panes as pane}
            <div
              class="workspace-tab-item"
              class:active={activePane === pane.id}
              style={`--tab-accent: ${pane.accent}`}
            >
              <button
                class="workspace-tab"
                type="button"
                id={`tab-${pane.id}`}
                role="tab"
                aria-selected={activePane === pane.id}
                aria-controls="terminal-grid"
                onclick={() => selectPane(pane.id)}
              >
                <span class="tab-dot"></span>
                <span class="tab-label">{pane.repo}</span>
                <span class="tab-branch">{pane.branch}</span>
              </button>
              <button
                class="tab-close"
                type="button"
                aria-label={`Close ${pane.repo} terminal`}
                title={`Close ${pane.repo}`}
                onclick={event => {
                  event.stopPropagation()
                  closePane(pane.id)
                }}
              >×</button>
            </div>
          {/each}
          <button
            class="add-session"
            type="button"
            aria-label="Add terminal session"
            title="Add terminal session"
            onclick={addPane}
          >+</button>
        </div>

        <div class="terminal-grid" id="terminal-grid" role="tabpanel">
          {#each panes as pane}
            <TerminalPane {...pane} onActivate={() => selectPane(pane.id)} />
          {/each}
        </div>

        <footer class="window-footer">
          <span>{panes.length} {panes.length === 1 ? 'terminal' : 'terminals'}</span>
        </footer>
      </div>
    </section>

    <section class="details" id="details" aria-labelledby="workspace-title">
      <div class="feature-heading">
        <h2 id="workspace-title">The macOS app</h2>
        <a href="https://github.com/Envl/colerm/releases">Release notes ↗</a>
      </div>
      <img
        class="workspace-screenshot"
        src="/colerm-workspace.png"
        alt="Colerm workspace showing Running and Done agent badges beside a split Git diff"
        width="3328"
        height="1814"
        loading="lazy"
      />
      <div class="feature-grid">
        <div><h3>Git branches and diffs</h3><p>Switch branches from the terminal header. Review uncommitted changes in a unified or split view with sticky file titles and <kbd>⌘F</kbd> search.</p></div>
        <div><h3>Coding agent status</h3><p>Tabs show when a detected agent such as Claude Code or Codex is running, needs input or approval, or has finished.</p></div>
        <div><h3>Columns and tabs</h3><p>Resize columns, reorder tabs, or move tabs to a resizable sidebar. Colerm reopens fresh shells in your saved working directories.</p></div>
        <div><h3>Terminal navigation</h3><p>Find sessions with <kbd>⌘P</kbd> or select by position with <kbd>⌘1</kbd> through <kbd>⌘9</kbd>. Customize the palette and cycling shortcuts in Settings.</p></div>
        <div><h3>Running commands</h3><p>See which terminals are busy and jump to one from the workspace footer. Each column shows its working directory and Git status.</p></div>
        <div><h3>File and image paste</h3><p>Paste or drop Finder files to insert shell-escaped paths. Paste an image to insert a path to a temporary PNG.</p></div>
      </div>
    </section>
  </main>

  <footer class="site-footer">
    <span>Colerm</span>
  </footer>
</div>

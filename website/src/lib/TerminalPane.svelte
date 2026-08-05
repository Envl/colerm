<script lang="ts">
  import { onMount } from 'svelte'
  import { enableCaseInsensitiveCompletion } from './case-insensitive-terminal-completion'

  type TerminalInstance = {
    destroy: () => void
    init: () => Promise<unknown>
    write: (data: string | Uint8Array) => void
  }

  type ShellInstance = {
    attach: (write: (data: string) => void) => Promise<void>
    handleInput: (data: string) => Promise<void>
  }

  let {
    id,
    repo,
    path,
    branch,
    gitState,
    diff,
    accent,
    cwd,
    intro,
    files,
    startupCommands,
    onActivate,
  }: {
    id: string
    repo: string
    path: string
    branch: string
    gitState: string
    diff: string
    accent: string
    cwd: string
    intro: string[]
    files: Record<string, string>
    startupCommands?: string[]
    onActivate?: () => void
  } = $props()

  let host = $state<HTMLDivElement>()
  let errorMessage = $state('')

  onMount(() => {
    let active = true
    let terminal: TerminalInstance | undefined
    let shell: ShellInstance | undefined

    async function setup() {
      if (!host) return

      try {
        const [{ WTerm }, { BashShell }] = await Promise.all([
          import('@wterm/dom'),
          import('@wterm/just-bash'),
        ])

        await new Promise<void>(resolve => {
          requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
        })
        if (!active || !host) return

        const rowHeight = 17
        const charWidth = rowHeight * 0.62
        const cols = Math.max(44, Math.floor(host.clientWidth / charWidth))
        const rows = Math.max(10, Math.floor(host.clientHeight / rowHeight))

        terminal = new WTerm(host, {
          autoResize: false,
          cols,
          rows,
          cursorBlink: true,
          onData: (data: string) => {
            void shell?.handleInput(data)
          },
        })
        await terminal.init()
        if (!active) return

        terminal.write(`${intro.join('\r\n')}\r\n`)

        const bashShell = new BashShell({
          cwd,
          files,
          greeting: [],
          prompt: () =>
            `\x1b[38;5;${accent === '#78dcca' ? '79' : accent === '#d2a8ff' ? '183' : '114'}m❯\x1b[0m `,
        })
        enableCaseInsensitiveCompletion(bashShell)
        shell = bashShell
        await shell.attach(data => {
          if (active) terminal?.write(data)
        })

        for (const command of startupCommands ?? []) {
          await shell.handleInput(`${command}\r`)
        }
      } catch (error) {
        errorMessage =
          error instanceof Error ? error.message : 'Terminal failed to load'
      }
    }

    void setup()

    return () => {
      active = false
      terminal?.destroy()
      terminal = undefined
      shell = undefined
    }
  })
</script>

<article
  class="terminal-pane"
  style={`--pane-accent: ${accent}`}
  id={`terminal-${id}`}
  onpointerdown={() => onActivate?.()}
>
  <header class="pane-header">
    <div class="pane-title">
      <span class="repo-mark" aria-hidden="true">{repo.slice(0, 1)}</span>
      <div>
        <strong>{repo}</strong>
        <span>{path}</span>
      </div>
    </div>
    <div class="pane-status" aria-label={`${gitState}, ${diff} changed files`}>
      <span class="status-dot" aria-hidden="true"></span>
      <span>{gitState}</span>
      <b>{diff}</b>
    </div>
  </header>

  <div class="pane-meta">
    <span class="branch-symbol" aria-hidden="true">⌘</span>
    <span>{branch}</span>
    <span class="meta-divider"></span>
    <span>{cwd}</span>
  </div>

  <div class="terminal-host" bind:this={host} aria-label={`${repo} interactive terminal`}></div>
  {#if errorMessage}
    <p class="terminal-error">Terminal unavailable: {errorMessage}</p>
  {/if}
</article>

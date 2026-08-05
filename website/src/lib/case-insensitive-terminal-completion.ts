type BashResult = {
  exitCode: number
  stdout?: string
}

type BashLike = {
  exec: (
    command: string,
    options?: { cwd?: string },
  ) => Promise<BashResult>
}

type BashShellInternals = {
  _bash: BashLike | null
  _cwd: string
  _cursor: number
  _line: string
  _prompt: (cwd: string) => string
  _tabComplete: () => Promise<void>
  _write: ((data: string) => void) | null
}

function caseInsensitiveMatches(candidates: string[], prefix: string) {
  const normalizedPrefix = prefix.toLocaleLowerCase()
  return candidates.filter(candidate =>
    candidate.toLocaleLowerCase().startsWith(normalizedPrefix),
  )
}

function caseInsensitiveCommonPrefix(candidates: string[]) {
  if (!candidates.length) return ''

  let common = candidates[0]
  for (const candidate of candidates.slice(1)) {
    while (
      common &&
      !candidate.toLocaleLowerCase().startsWith(common.toLocaleLowerCase())
    ) {
      common = common.slice(0, -1)
    }
  }
  return common
}

function replaceWord(
  shell: BashShellInternals,
  wordStart: number,
  replacement: string,
) {
  const write = shell._write
  if (!write) return

  const oldCursor = shell._cursor
  const oldWordLength = oldCursor - wordStart
  const tail = shell._line.slice(oldCursor)
  shell._line = shell._line.slice(0, wordStart) + replacement + tail
  shell._cursor = wordStart + replacement.length

  if (oldWordLength) write(`\x1b[${oldWordLength}D`)
  write(`${replacement}${tail}\x1b[K`)
  if (tail.length) write(`\x1b[${tail.length}D`)
}

function resolveDirectory(cwd: string, rawDirectory: string) {
  if (rawDirectory.startsWith('/')) return rawDirectory
  if (rawDirectory.startsWith('~/')) {
    return `/home/user/${rawDirectory.slice(2)}`
  }
  return `${cwd}/${rawDirectory}`
}

export function enableCaseInsensitiveCompletion(shell: object) {
  const internals = shell as BashShellInternals

  internals._tabComplete = async () => {
    const bash = internals._bash
    const write = internals._write
    if (!bash || !write) return

    const beforeCursor = internals._line.slice(0, internals._cursor)
    const parts = beforeCursor.split(/\s+/)
    const word = parts[parts.length - 1] ?? ''
    const wordStart = internals._cursor - word.length
    const isFirst = parts.length <= 1
    const slashIndex = word.lastIndexOf('/')
    const rawDirectory =
      slashIndex >= 0 ? word.slice(0, slashIndex + 1) : ''
    const prefix = slashIndex >= 0 ? word.slice(slashIndex + 1) : word
    const directory = resolveDirectory(internals._cwd, rawDirectory)

    let candidates: string[] = []
    try {
      const result = await bash.exec(`ls -1a ${JSON.stringify(directory)}`, {
        cwd: internals._cwd,
      })
      if (result.exitCode === 0 && result.stdout) {
        const entries = result.stdout
          .split('\n')
          .filter(entry => entry && entry !== '.' && entry !== '..')
        candidates = caseInsensitiveMatches(entries, prefix)
      }
    } catch {
      return
    }

    if (isFirst && !word.includes('/')) {
      for (const commandDirectory of ['/bin', '/usr/bin']) {
        try {
          const result = await bash.exec(
            `ls -1 ${JSON.stringify(commandDirectory)}`,
            { cwd: internals._cwd },
          )
          if (result.exitCode === 0 && result.stdout) {
            const commands = caseInsensitiveMatches(
              result.stdout.split('\n').filter(Boolean),
              prefix,
            )
            for (const command of commands) {
              if (!candidates.includes(command)) candidates.push(command)
            }
          }
        } catch {
          // Continue with whichever virtual command directories are available.
        }
      }

      try {
        const result = await bash.exec('compgen -c 2>/dev/null || true', {
          cwd: internals._cwd,
        })
        if (result.exitCode === 0 && result.stdout) {
          const commands = caseInsensitiveMatches(
            result.stdout.split('\n').filter(Boolean),
            prefix,
          )
          for (const command of commands) {
            if (!candidates.includes(command)) candidates.push(command)
          }
        }
      } catch {
        // The virtual shell may not expose compgen.
      }
    }

    if (!candidates.length) return

    if (candidates.length === 1) {
      let completedWord = `${rawDirectory}${candidates[0]}`
      replaceWord(internals, wordStart, completedWord)

      try {
        const path = resolveDirectory(internals._cwd, completedWord)
        const result = await bash.exec(
          `test -d ${JSON.stringify(path)} && echo DIR`,
          { cwd: internals._cwd },
        )
        if (
          result.stdout?.trim() === 'DIR' &&
          !internals._line.slice(0, internals._cursor).endsWith('/')
        ) {
          completedWord += '/'
          replaceWord(internals, wordStart, completedWord)
        }
      } catch {
        // Completion remains valid if the directory probe fails.
      }
      return
    }

    const commonPrefix = caseInsensitiveCommonPrefix(candidates)
    if (commonPrefix.length > prefix.length) {
      replaceWord(internals, wordStart, `${rawDirectory}${commonPrefix}`)
      return
    }

    write(`\r\n${candidates.join(' ')}\r\n`)
    write(internals._prompt(internals._cwd))
    write(internals._line)
  }
}

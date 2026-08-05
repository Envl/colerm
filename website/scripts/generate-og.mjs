import { readFile, writeFile } from 'node:fs/promises'
import { ImageResponse } from '@vercel/og'
import React from 'react'

const h = React.createElement
const logo = `data:image/png;base64,${(await readFile(new URL('../static/colerm-logo-1024.png', import.meta.url))).toString('base64')}`

const image = new ImageResponse(
  h(
    'div',
    {
      style: {
        width: '100%',
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        position: 'relative',
        overflow: 'hidden',
        background: '#090909',
        color: '#f4f4f1',
        fontFamily: 'sans-serif',
      },
    },
    h(
      'div',
      {
        style: {
          display: 'flex',
          alignItems: 'center',
          gap: 12,
          position: 'absolute',
          top: 42,
          left: 64,
          color: '#f4f4f1',
          fontSize: 24,
          fontWeight: 700,
          letterSpacing: -1,
        },
      },
      h('img', { src: logo, width: 30, height: 30, style: { borderRadius: 8 } }),
      'Colerm',
    ),
    h(
      'div',
      {
      style: {
        display: 'flex',
        position: 'absolute',
        top: 142,
        left: 64,
        whiteSpace: 'nowrap',
      },
    },
      h(
        'div',
        { style: { display: 'flex', fontSize: 86, fontWeight: 600, letterSpacing: -6, lineHeight: 0.95 } },
        'Terminals,',
        h('span', { style: { display: 'flex', color: '#7f7f79' } }, ' in focus.'),
      ),
    ),
    h(
      'div',
      {
        style: {
          display: 'flex',
          position: 'absolute',
          top: 252,
          left: 68,
          maxWidth: 1040,
          color: '#999994',
          fontSize: 44,
          lineHeight: 1.25,
          letterSpacing: -0.5,
        },
      },
      'Every project, prompt, and running process visible in one calm workspace.',
    ),
    h(
      'div',
      {
        style: {
          display: 'flex',
          position: 'absolute',
          right: 64,
          bottom: 48,
          left: 64,
          height: 146,
          overflow: 'hidden',
          border: '1px solid #2e2e2e',
          borderRadius: 12,
          background: '#151515',
        },
      },
      ...[
        ['#78dcca', 'colerm', 'main', '$ swift build', 'Build complete!'],
        ['#c4a7ff', 'pinchkey', 'release/1.0.38', '$ git status', 'working tree clean'],
        ['#f89ab4', 'pulsebar', 'polish-menu', '$ pnpm check', '0 errors, 0 warnings'],
      ].map(([accent, name, branch, command, result], index) =>
        h(
          'div',
          {
            key: name,
            style: {
              display: 'flex',
              flexDirection: 'column',
              flex: 1,
              gap: 12,
              padding: '18px 22px',
              borderRight: index === 2 ? '0' : '1px solid #292929',
              color: '#777772',
              fontSize: 16,
            },
          },
          h('div', { style: { display: 'flex', alignItems: 'center', gap: 8, color: '#d9d9d4', fontWeight: 600 } }, h('span', { style: { width: 8, height: 8, borderRadius: 4, background: accent } }), name, h('span', { style: { color: '#686863', fontSize: 13, fontWeight: 400 } }, branch)),
          h('div', { style: { display: 'flex', color: accent } }, command),
          h('div', { style: { display: 'flex', color: '#74d49e' } }, result),
        ),
      ),
    ),
  ),
  { width: 1200, height: 630 },
)

await writeFile(new URL('../static/og.png', import.meta.url), Buffer.from(await image.arrayBuffer()))

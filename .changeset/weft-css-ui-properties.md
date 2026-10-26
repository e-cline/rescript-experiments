---
'@e-cline/weft_css': patch
---

A variable's initial value (`Css.var`) is declared on `:where(:root)`, not `:root`, so a value set
for it anywhere else (a component library's default overridden by an app's `:root`, say) wins
whichever sheet loads first. New properties: the logical ones (`insetInline*`, `insetBlock*`,
`inlineSize`, `blockSize` and their minimums and maximums, `marginInline*`, `marginBlock*`,
`paddingInline*`, `paddingBlock*`, `borderInline*`, `borderBlock*`, `borderStartStartRadius` and the
other corners), anchor positioning (`anchorName`, `positionAnchor`, `positionArea`, `positionTry`,
`positionTryFallbacks`), and `isolation`, `textOverflow`, `textWrap`, `overflowWrap`,
`textUnderlineOffset`, `verticalAlign`, `captionSide`, `borderCollapse`, `borderSpacing`,
`colorScheme`, `accentColor`, `appearance`, `overscrollBehavior`, `resize`, `translate`, `scale`,
`transformOrigin`, `counterReset` and `counterIncrement`.

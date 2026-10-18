@@directive("'use weft entrypoint'")

type props = {src: string, children: WeftCore.Element.t}

let make = ({src, children}: props) => {
  let {element, refetch, isPending}: Navigation.refetchable = Navigation.useRefetchable(
    ~src,
    children,
  )
  let frame = WeftCore.Hooks.useMemo2(
    (): Navigation.frame => {refetch, isPending},
    (refetch, isPending),
  )
  Navigation.withFrame(frame, element)
}

WeftCore.Entrypoint.mark(make, "@e-cline/weft_server/src/Frame.res#")

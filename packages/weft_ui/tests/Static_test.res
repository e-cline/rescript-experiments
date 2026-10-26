/***
The static components, rendered as a server component's output is (`WeftServer.Render`, which fails
on any hook): every one renders there, with its classes in the payload, which is how the server
knows to send their stylesheets.
*/
open Vitest
open Support

module UsesState = {
  /** The control: a component with state, which a server render refuses. */
  @weft.component
  let make = () => {
    let (count, _) = Weft.Hooks.useState(() => 0)
    text(Int.toString(count))
  }
}

let everything =
  <Container size=#md>
    <Stack gap=#lg>
      <Heading level=#h1> {text("Title")} </Heading>
      <Text tone=#muted size=#sm> {text("Muted")} </Text>
      <Link href="/a" external_=true> {text("A link")} </Link>
      <VisuallyHidden> {text("Hidden")} </VisuallyHidden>
      <Separator />
      <Grid minItemWidth="200px">
        <Card.Root as_=#article interactive=true>
          <Card.Header>
            <Card.Title> {text("Card")} </Card.Title>
            <Card.Description> {text("About it")} </Card.Description>
          </Card.Header>
          <Card.Content> {text("Content")} </Card.Content>
          <Card.Footer>
            <Badge tone=#success> {text("In stock")} </Badge>
          </Card.Footer>
        </Card.Root>
      </Grid>
      <Alert.Root tone=#danger>
        <Alert.Title> {text("Failed")} </Alert.Title>
        <Alert.Description> {text("Why")} </Alert.Description>
        <Alert.Action>
          <Button> {text("Retry")} </Button>
        </Alert.Action>
      </Alert.Root>
      <EmptyState.Root bordered=true>
        <EmptyState.Title> {text("Nothing here")} </EmptyState.Title>
        <EmptyState.Description> {text("Yet")} </EmptyState.Description>
      </EmptyState.Root>
      <Table.Root scrollLabel="Orders">
        <Table.Caption hidden=true> {text("Orders")} </Table.Caption>
        <Table.Head>
          <Table.Row>
            <Table.HeaderCell> {text("Order")} </Table.HeaderCell>
            <Table.HeaderCell numeric=true> {text("Total")} </Table.HeaderCell>
          </Table.Row>
        </Table.Head>
        <Table.Body>
          <Table.Row>
            <Table.Cell> {text("A1")} </Table.Cell>
            <Table.Cell numeric=true> {text("$4")} </Table.Cell>
          </Table.Row>
        </Table.Body>
      </Table.Root>
      <List.Root divided=true>
        <List.Item> {text("One")} </List.Item>
      </List.Root>
      <DescriptionList.Root detailsAlign=#end>
        <DescriptionList.Term> {text("Subtotal")} </DescriptionList.Term>
        <DescriptionList.Details> {text("$4")} </DescriptionList.Details>
      </DescriptionList.Root>
      <Breadcrumbs.Root>
        <Breadcrumbs.Item>
          <Link href="/"> {text("Home")} </Link>
        </Breadcrumbs.Item>
        <Breadcrumbs.Current> {text("Here")} </Breadcrumbs.Current>
      </Breadcrumbs.Root>
      <Steps.Root ariaLabel="Checkout">
        <Steps.Step status=#complete> {text("Address")} </Steps.Step>
        <Steps.Step status=#current> {text("Delivery")} </Steps.Step>
      </Steps.Root>
      <Spinner />
      <Skeleton lines=2 />
      <Button variant=#primary busy=true> {text("Saving")} </Button>
      <IconButton label="Close"> {text("×")} </IconButton>
    </Stack>
  </Container>

describe("rendered by the server", () => {
  testAsync("every static component renders, with no hooks", async t => {
    let (payload, errors) = await serverRender(everything)
    t->expect(errors->Array.length)->Expect.toBe(0)
    [
      Container.Styles.container,
      Stack.Styles.stack,
      Heading.Styles.heading,
      Text.Styles.muted,
      Link.Styles.link,
      VisuallyHidden.Styles.hidden,
      Separator.Styles.separator,
      Grid.Styles.grid,
      Card.Styles.root,
      Badge.Styles.badge,
      Alert.Styles.root,
      EmptyState.Styles.root,
      Table.Styles.table,
      List.Styles.list,
      DescriptionList.Styles.list,
      Breadcrumbs.Styles.list,
      Steps.Styles.step,
      Spinner.Styles.spinner,
      Skeleton.Styles.skeleton,
      Button.Styles.primary,
      Button.Styles.square,
    ]->Array.forEach(
      className =>
        t
        ->expect((className, payload->String.includes(className)))
        ->Expect.toEqual((className, true)),
    )
  })

  testAsync("a component with state doesn't (the control)", async t => {
    let (_, errors) = await serverRender(
      <div>
        <UsesState />
      </div>,
    )
    t->expect(errors->Array.length)->Expect.toBe(1)
  })
})

# Examples

Use the repository examples when you want complete, buildable code instead of isolated snippets.

The canonical sample is `Examples/ProjectBrowser`. It models an AniCanon-style project browser with records, hydrated models, relationships, enum resources, repository injection, testing, and scheduled refresh registration.

Run it from the repository root:

```sh
scripts/examples.sh
```

Or run the sample directly:

```sh
cd Examples/ProjectBrowser
swift run ProjectBrowser
swift test
```

The sample uses `FakeKomaTransport` so it can run without a backend. In an app, keep the same repository and resource code and replace the transport at the composition root with `URLSessionKomaTransport`.

# a2a-backend-grpc

gRPC binding for [`a2a-protocol`](https://github.com/egao1980/a2a-protocol) via
[`rpc-protocol-grpc`](https://github.com/egao1980/rpc-protocol-grpc).

Official service path: `/lf.a2a.v1.A2AService/{SendMessage,SendStreamingMessage,GetTask,ListTasks,CancelTask,SubscribeToTask,GetExtendedAgentCard}`.

Wave-1 payloads are the same JSON objects as JSON-RPC until the official
`specification/a2a.proto` is compiled. Do **not** call `grpc-protocol` from
this package — only `rpc-protocol-grpc`.

```lisp
;; same-image loopback
(let ((backend (a2a-backend-grpc:make-grpc-a2a-backend
                :agent (a2a-protocol:make-a2a-agent :name "echo"))))
  (a2a-protocol:send-message backend
                             (a2a-protocol:make-a2a-message :text "hi")))

;; remote (needs a grpc-protocol backend bound)
(a2a-backend-grpc:make-grpc-a2a-backend :target "127.0.0.1:8080")
```

Part of [cl-stack](https://github.com/egao1980/cl-stack) agent-wire
([brief](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/a2a.md)).
Tracks [#186](https://github.com/egao1980/cl-stack/issues/186).

CI: canned [`cl-repository`](https://github.com/egao1980/cl-repository)
(`test-system.yml`). Deps from `ghcr.io/egao1980/cl-systems`.

## License

MIT

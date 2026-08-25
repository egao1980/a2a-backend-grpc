(defsystem "a2a-backend-grpc"
  :version "0.1.0"
  :description "gRPC / protobuf binding for a2a-protocol"
  :author "egao1980"
  :license "MIT"
  :depends-on ("a2a-protocol" "rpc-protocol" "rpc-protocol-grpc"
               "grpc-protocol" "protobuf-protocol")
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "backend"))
  :in-order-to ((test-op (test-op "a2a-backend-grpc/tests"))))

(defsystem "a2a-backend-grpc/tests"
  :depends-on ("a2a-backend-grpc" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "backend-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))

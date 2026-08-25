(in-package #:a2a-backend-grpc/tests)

(deftest backend-class
  (ok (typep (a2a-backend-grpc:make-grpc-a2a-backend) 'a2a-backend-grpc:grpc-a2a-backend)))

(deftest connects-via-rpc-protocol-grpc
  (ok (null (a2a-backend-grpc:backend-transport
             (a2a-backend-grpc:make-grpc-a2a-backend)))))

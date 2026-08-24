(defpackage #:a2a-backend-grpc
  (:use #:cl)
  (:export #:grpc-a2a-backend
           #:make-grpc-a2a-backend
           #:use-grpc-a2a-backend
           #:backend-transport
           #:backend-target))

(in-package #:a2a-backend-grpc)

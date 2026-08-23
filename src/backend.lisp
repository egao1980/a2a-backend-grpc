(in-package #:a2a-backend-grpc)

(defclass grpc-a2a-backend (a2a-protocol:a2a-backend) ())

(defun make-grpc-a2a-backend ()
  (make-instance 'grpc-a2a-backend))

(defun use-grpc-a2a-backend ()
  (setf a2a-protocol:*a2a-backend* (make-grpc-a2a-backend)))

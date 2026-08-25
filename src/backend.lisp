(in-package #:a2a-backend-grpc)

;;; gRPC binding is rpc-protocol-grpc — do not call grpc-protocol from here.

(defclass grpc-a2a-backend (a2a-protocol:a2a-backend)
  ((transport :initarg :transport :accessor backend-transport :initform nil)
   (target :initarg :target :accessor backend-target :initform nil)))

(defun make-grpc-a2a-backend (&key target transport
                                (backend grpc-protocol:*grpc-backend*))
  (make-instance 'grpc-a2a-backend
                 :target target
                 :transport (or transport
                                (when target
                                  (rpc-protocol-grpc:grpc-rpc-connect
                                   target :backend backend)))))

(defun use-grpc-a2a-backend (&rest args &key &allow-other-keys)
  (setf a2a-protocol:*a2a-backend* (apply #'make-grpc-a2a-backend args)))

(defun %transport (backend)
  (or (backend-transport backend)
      (when (backend-target backend)
        (setf (backend-transport backend)
              (rpc-protocol-grpc:grpc-rpc-connect (backend-target backend))))
      rpc-protocol:*rpc-transport*
      (error 'a2a-protocol:a2a-error
             :message "grpc A2A backend has no rpc-protocol-grpc transport")))

(defun %rpc (backend method params)
  (handler-case
      (rpc-protocol:rpc-call method params :transport (%transport backend))
    (rpc-protocol:rpc-error (c)
      (error 'a2a-protocol:a2a-error
             :message (rpc-protocol:rpc-error-message c)
             :code (rpc-protocol:rpc-error-code c)
             :data (rpc-protocol:rpc-error-data c)))))

(defmethod a2a-protocol:send-message ((backend grpc-a2a-backend) message
                                      &key task-id (blocking t))
  (when task-id
    (setf (a2a-protocol:a2a-message-task-id message) task-id))
  (a2a-protocol:decode-send-result
   (%rpc backend "SendMessage"
         (a2a-protocol:json-object
          "message" (a2a-protocol:encode-message message)
          "configuration" (if blocking
                              :omit
                              (a2a-protocol:json-object "returnImmediately" t))))))

(use-grpc-a2a-backend)

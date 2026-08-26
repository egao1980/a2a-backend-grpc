(in-package #:a2a-backend-grpc)

;;; gRPC binding is rpc-protocol-grpc — do not call grpc-protocol from here.
;;; Official service: lf.a2a.v1.A2AService (specification/a2a.proto).
;;; Wave-1 payloads are the same JSON objects as JSON-RPC until the proto is compiled.

(defparameter +a2a-grpc-service+ "/lf.a2a.v1.A2AService")

(defclass grpc-a2a-backend (a2a-protocol:a2a-backend)
  ((transport :initarg :transport :accessor backend-transport :initform nil)
   (target :initarg :target :accessor backend-target :initform nil)
   (agent :initarg :agent :accessor backend-agent :initform nil)
   (card :initarg :card :accessor backend-card :initform nil)))

(defun make-grpc-a2a-backend (&key target transport agent card backend)
  (make-instance 'grpc-a2a-backend
                 :target target
                 :agent agent
                 :card card
                 :transport (or transport
                                (when target
                                  (apply #'rpc-protocol-grpc:grpc-rpc-connect
                                         target
                                         (when backend (list :backend backend)))))))

(defun use-grpc-a2a-backend (&rest args &key &allow-other-keys)
  (setf a2a-protocol:*a2a-backend* (apply #'make-grpc-a2a-backend args)))

(defun grpc-method (name)
  (format nil "~a/~a" +a2a-grpc-service+ name))

(defun %local (backend)
  (backend-agent backend))

(defun %transport (backend)
  (or (backend-transport backend)
      (when (backend-target backend)
        (setf (backend-transport backend)
              (rpc-protocol-grpc:grpc-rpc-connect (backend-target backend))))
      rpc-protocol:*rpc-transport*
      (a2a-protocol:signal-a2a-error
       :message "grpc A2A backend has no :agent, :target, or rpc-protocol-grpc transport")))

(defun %rpc (backend method params)
  (handler-case
      (rpc-protocol:rpc-call (grpc-method method) params
                             :transport (%transport backend))
    (rpc-protocol:rpc-error (c)
      (a2a-protocol:signal-a2a-error
       :message (rpc-protocol:rpc-error-message c)
       :code (rpc-protocol:rpc-error-code c)
       :data (rpc-protocol:rpc-error-data c)))))

(defun %rpc-stream (backend method params)
  (let ((stream (rpc-protocol:rpc-call-stream (grpc-method method) params
                                              :transport (%transport backend))))
    (unwind-protect
         (loop for ev = (rpc-protocol:rpc-recv stream)
               until (eq ev :eof)
               collect ev)
      (rpc-protocol:rpc-close stream))))

(defun %events (result)
  (cond
    ((typep result 'a2a-protocol:a2a-stream-result)
     (a2a-protocol:a2a-stream-events result))
    ((listp result) result)
    (t (list result))))

(defmethod a2a-protocol:fetch-agent-card ((backend grpc-a2a-backend) url &key)
  (declare (ignore url))
  (or (backend-card backend)
      (when (%local backend)
        (a2a-protocol:a2a-agent-card (%local backend)))
      (let ((card (a2a-protocol:decode-agent-card
                   (%rpc backend "GetExtendedAgentCard"
                         (a2a-protocol:json-object)))))
        (setf (backend-card backend) card)
        card)))

(defmethod a2a-protocol:serve-agent-card ((backend grpc-a2a-backend) card &key)
  (setf (backend-card backend) card)
  (when (%local backend)
    (a2a-protocol:serve-agent-card (%local backend) card))
  card)

(defmethod a2a-protocol:send-message ((backend grpc-a2a-backend) message
                                      &key task-id (blocking t))
  (when task-id
    (setf (a2a-protocol:a2a-message-task-id message) task-id))
  (if (%local backend)
      (a2a-protocol:send-message (%local backend) message
                                 :task-id task-id :blocking blocking)
      (a2a-protocol:decode-send-result
       (%rpc backend "SendMessage"
             (a2a-protocol:json-object
              "message" (a2a-protocol:encode-message message)
              "configuration" (if blocking
                                  :omit
                                  (a2a-protocol:json-object "returnImmediately" t)))))))

(defmethod a2a-protocol:stream-message ((backend grpc-a2a-backend) message
                                        &key on-event)
  (let ((events (if (%local backend)
                    (a2a-protocol:a2a-stream-events
                     (a2a-protocol:stream-message (%local backend) message))
                    (%rpc-stream backend "SendStreamingMessage"
                                 (a2a-protocol:json-object
                                  "message" (a2a-protocol:encode-message message))))))
    (when on-event
      (mapc on-event events))
    (a2a-protocol:make-a2a-stream-result events)))

(defmethod a2a-protocol:get-task ((backend grpc-a2a-backend) task-id
                                  &key history-length)
  (if (%local backend)
      (a2a-protocol:get-task (%local backend) task-id
                             :history-length history-length)
      (a2a-protocol:decode-task
       (%rpc backend "GetTask"
             (a2a-protocol:json-object
              "id" task-id
              "historyLength" (or history-length :omit))))))

(defmethod a2a-protocol:list-tasks ((backend grpc-a2a-backend)
                                    &key context-id status page-size page-token
                                      history-length include-artifacts
                                      status-timestamp-after)
  (if (%local backend)
      (a2a-protocol:list-tasks (%local backend)
                               :context-id context-id :status status
                               :page-size page-size :page-token page-token
                               :history-length history-length
                               :include-artifacts include-artifacts
                               :status-timestamp-after status-timestamp-after)
      (%rpc backend "ListTasks"
            (a2a-protocol:json-object
             "contextId" (or context-id :omit)
             "status" (if status (a2a-protocol:task-state-to-wire status) :omit)
             "pageSize" (or page-size :omit)
             "pageToken" (or page-token :omit)
             "historyLength" (or history-length :omit)
             "includeArtifacts" (if include-artifacts t :omit)
             "statusTimestampAfter" (or status-timestamp-after :omit)))))

(defmethod a2a-protocol:cancel-task ((backend grpc-a2a-backend) task-id &key)
  (if (%local backend)
      (a2a-protocol:cancel-task (%local backend) task-id)
      (a2a-protocol:decode-task
       (%rpc backend "CancelTask" (a2a-protocol:json-object "id" task-id)))))

(defmethod a2a-protocol:resubscribe-task ((backend grpc-a2a-backend) task-id
                                          &key on-event)
  (let ((events (if (%local backend)
                    (a2a-protocol:a2a-stream-events
                     (a2a-protocol:resubscribe-task (%local backend) task-id))
                    (%rpc-stream backend "SubscribeToTask"
                                 (a2a-protocol:json-object "id" task-id)))))
    (when on-event
      (mapc on-event events))
    (a2a-protocol:make-a2a-stream-result events)))

(use-grpc-a2a-backend)

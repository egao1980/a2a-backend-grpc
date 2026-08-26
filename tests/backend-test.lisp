(in-package #:a2a-backend-grpc/tests)

(defun %agent ()
  (a2a-protocol:make-a2a-agent :name "echo"))

(defun %msg (&optional (text "hi"))
  (a2a-protocol:make-a2a-message :text text))

;;; --- local :agent loopback ------------------------------------------------

(deftest backend-class
  (ok (typep (a2a-backend-grpc:make-grpc-a2a-backend)
             'a2a-backend-grpc:grpc-a2a-backend)))

(deftest grpc-method-path
  (ok (equal "/lf.a2a.v1.A2AService/SendMessage"
             (a2a-backend-grpc:grpc-method "SendMessage"))))

(deftest local-send-get-cancel
  (let* ((agent (%agent))
         (backend (a2a-backend-grpc:make-grpc-a2a-backend :agent agent))
         (task (a2a-protocol:send-message backend (%msg "pong"))))
    (ok (eq :completed (a2a-protocol:a2a-task-state task)))
    (let ((got (a2a-protocol:get-task backend (a2a-protocol:a2a-task-id task))))
      (ok (equal (a2a-protocol:a2a-task-id task)
                 (a2a-protocol:a2a-task-id got))))
    (let ((listed (a2a-protocol:list-tasks backend :page-size 10)))
      (ok (eql 1 (getf listed :total-size))))))

(deftest local-stream
  (let* ((backend (a2a-backend-grpc:make-grpc-a2a-backend :agent (%agent)))
         (seen '())
         (result (a2a-protocol:stream-message backend (%msg "stream")
                                             :on-event (lambda (ev)
                                                         (push ev seen)))))
    (ok (typep result 'a2a-protocol:a2a-stream-result))
    (ok (= 3 (length (a2a-protocol:a2a-stream-events result))))
    (ok (= 3 (length seen)))))

(deftest local-card
  (let* ((agent (%agent))
         (backend (a2a-backend-grpc:make-grpc-a2a-backend :agent agent))
         (card (a2a-protocol:fetch-agent-card backend "unused")))
    (ok (equal "echo" (a2a-protocol:agent-card-name card)))))

(deftest missing-remote-errors
  (ok (signals (a2a-protocol:send-message
                (a2a-backend-grpc:make-grpc-a2a-backend)
                (%msg "x"))
               'a2a-protocol:a2a-error)))

;;; --- remote via mock grpc-protocol ----------------------------------------

(defclass loopback-backend (grpc-protocol:grpc-backend)
  ((agent :initarg :agent :accessor loopback-agent)))

(defclass loopback-channel (grpc-protocol:grpc-channel) ())

(defclass loopback-stream (grpc-protocol:grpc-stream)
  ((inbox :initarg :inbox :initform nil :accessor loopback-inbox)))

(defun %short-method (path)
  (let ((slash (position #\/ path :from-end t)))
    (if slash (subseq path (1+ slash)) path)))

(defmethod grpc-protocol:backend-grpc-connect ((backend loopback-backend) target
                                               &key credentials metadata)
  (make-instance 'loopback-channel
                 :target target
                 :backend backend
                 :credentials credentials
                 :metadata metadata))

(defmethod grpc-protocol:backend-grpc-call ((channel loopback-channel) method request
                                            &key timeout metadata)
  (declare (ignore timeout metadata))
  (let ((result (a2a-protocol:dispatch-a2a-method
                 (loopback-agent (grpc-protocol:grpc-channel-backend channel))
                 (%short-method method)
                 request
                 :protocol-version "1.0")))
    (if (typep result 'a2a-protocol:a2a-stream-result)
        (a2a-protocol:a2a-stream-events result)
        result)))

(defmethod grpc-protocol:backend-grpc-stream ((channel loopback-channel) method
                                              &key metadata)
  (declare (ignore metadata))
  (make-instance 'loopback-stream :channel channel :method method :inbox nil))

(defmethod grpc-protocol:grpc-send ((stream loopback-stream) message &key)
  (let* ((channel (grpc-protocol:grpc-stream-channel stream))
         (agent (loopback-agent (grpc-protocol:grpc-channel-backend channel)))
         (result (a2a-protocol:dispatch-a2a-method
                  agent
                  (%short-method (grpc-protocol:grpc-stream-method stream))
                  message
                  :protocol-version "1.0"))
         (events (if (typep result 'a2a-protocol:a2a-stream-result)
                     (a2a-protocol:a2a-stream-events result)
                     (list result))))
    (setf (loopback-inbox stream) (append (loopback-inbox stream) events))
    message))

(defmethod grpc-protocol:grpc-recv ((stream loopback-stream) &key timeout)
  (declare (ignore timeout))
  (or (pop (loopback-inbox stream)) :eof))

(defmethod grpc-protocol:grpc-close ((object t) &key)
  object)

(deftest remote-send-via-rpc-protocol-grpc
  (let* ((agent (%agent))
         (grpc (make-instance 'loopback-backend :agent agent))
         (backend (a2a-backend-grpc:make-grpc-a2a-backend
                   :target "localhost:1"
                   :backend grpc))
         (task (a2a-protocol:send-message backend (%msg "via-grpc"))))
    (ok (eq :completed (a2a-protocol:a2a-task-state task)))
    (ok (equal "/lf.a2a.v1.A2AService"
               a2a-backend-grpc:+a2a-grpc-service+))
    (let ((got (a2a-protocol:get-task backend (a2a-protocol:a2a-task-id task))))
      (ok (equal (a2a-protocol:a2a-task-id task)
                 (a2a-protocol:a2a-task-id got))))))

(deftest remote-stream-via-rpc-protocol-grpc
  (let* ((grpc (make-instance 'loopback-backend :agent (%agent)))
         (backend (a2a-backend-grpc:make-grpc-a2a-backend
                   :target "localhost:1"
                   :backend grpc))
         (result (a2a-protocol:stream-message backend (%msg "s"))))
    (ok (>= (length (a2a-protocol:a2a-stream-events result)) 1))))

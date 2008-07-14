
(in-package :hurd-common)

;;
;; This file implements the needed
;; abstractions to deal with the stat struct.
;;

;; POSIX.1b structure for a time value
;; Has seconds and nanoseconds.
;;
(defcstruct timespec-struct
  (sec :unsigned-int)
  (nsec :unsigned-int))

;; Just to be sure..
(assert (= (foreign-type-size 'timespec-struct) 8))

(defconstant +stat-size+ 128 "Size of a stat struct")

(defcstruct (stat-struct :size 128)
  "The stat struct."
	(fstype :unsigned-int) ; File system type
	(fsid :long-long) ; File system ID
	(ino ino-t) ; File number
	(gen :unsigned-int) ; To detect reuse of file numbers
	(rdev :unsigned-int) ; Device if special file
	(mode :unsigned-int) ; File mode
	(nlink :unsigned-int) ; Number of links
	(uid uid-t) ; Owner
	(gid gid-t) ; Owning group
	(size :long-long) ; Size in bytes
	(atim timespec-struct) ; Time of last access
	(mtim timespec-struct) ; Time of last modification
	(ctim timespec-struct) ; Time of last status change
	(blksize :unsigned-int) ; Optimal size of IO
	(blocks :long-long) ; Number of 512-byte blocks allocated
	(author uid-t) ; File author
	(flags :unsigned-int)) ; User defined flags

(defclass stat (base-mode)
  ((ptr :initform nil
        :initarg :ptr
        :accessor ptr
        :documentation "Pointer to a struct stat."))
  (:documentation "Class for objects containing a pointer to a stat struct."))

(defmethod mode-bits ((stat stat))
  "Returns the mode bits from a stat."
  (foreign-slot-value (ptr stat) 'stat-struct 'mode))

(defmethod (setf mode-bits) (new-value (stat stat))
  "Sets the mode bits from a stat."
  (setf (foreign-slot-value (ptr stat) 'stat-struct 'mode) new-value))

(defun stat-copy (stat-dest stat-src)
  "Copies to 'stat-dest' all the stat information from 'stat-src'."
  (memcpy (ptr stat-dest) (ptr stat-src) +stat-size+))

(defun %stat-time-get (ptr what)
  "Access from a 'ptr' stat struct the 'sec' field from the timespec field 'what'."
  (foreign-slot-value (foreign-slot-value ptr 'stat-struct what)
                      'timespec-struct 'sec))

(defmethod stat-get ((stat stat) what)
  "Gets specific information from a stat object.
'what' can be:
atime, mtime, ctime, dev, mode, fstype, fsid, ino, gen, rdev, nlink,
uid, gid, size, atim, mtim, ctim, blksize, blocks, author, flags."
  (with-slots ((ptr ptr)) stat
    (case what
      (atime (%stat-time-get ptr 'atim))
      (mtime (%stat-time-get ptr 'mtim))
      (ctime (%stat-time-get ptr 'ctim))
      ; Get type from the mode bits.
      (type (get-type stat))
      ; 'dev' is an alias to 'fsid'.
      (dev (foreign-slot-value ptr 'stat-struct 'fsid))
      ; we return a mode object here
      (mode (make-mode-clone
              (foreign-slot-value ptr 'stat-struct 'mode)))
      (otherwise
        (foreign-slot-value ptr 'stat-struct what)))))

(defun %stat-time-set (ptr field new-value)
  "From a stat pointer 'ptr' set the timespec field 'field' to 'new-value'."
  (let ((timespec (foreign-slot-value ptr 'stat-struct field))) ; Get the field
    (cond
      ((typep new-value 'time-value) ; Test if this is a kernel time-value
       ; Copy the time-value seconds
       ; and convert the microseconds to nanoseconds.
       (setf (foreign-slot-value timespec 'timespec-struct 'sec)
             (foreign-slot-value (ptr new-value) 'time-value-struct 'seconds)
             (foreign-slot-value timespec 'timespec-struct 'nsec)
             (* 1000
                (foreign-slot-value (ptr new-value)
                                    'time-value-struct 'microseconds)))
       t)
      ((eq new-value :now)
       ; Use *mapped-time* to update fields.
       (setf (foreign-slot-value timespec 'timespec-struct 'sec)
             (maptime-seconds *mapped-time*)
             (foreign-slot-value timespec 'timespec-struct 'nsec)
             (* 1000
                (maptime-microseconds *mapped-time*))))
      (t
        ; For everything else just copy the value to seconds.
        (setf (foreign-slot-value timespec 'timespec-struct 'sec)
              new-value)
        (setf (foreign-slot-value timespec 'timespec-struct 'nsec) 0)
        t))))

(defmethod stat-set ((stat stat) what new-value)
  "Sets a stat field 'what' to 'new-value'.
'what' can have the same values as 'stat-get'."
  (with-slots ((ptr ptr)) stat
    (case what
      (atime (%stat-time-set ptr 'atim new-value))
      (mtime (%stat-time-set ptr 'mtim new-value))
      (ctime (%stat-time-set ptr 'ctim new-value))
      ; Just an alias to fsid
      (dev (setf (foreign-slot-value ptr 'stat-struct 'fsid) new-value))
      (mode
        ; If 'new-value' is a mode object, copy its bits
        ; else it must be the mode bitfield itself.
        (setf (foreign-slot-value ptr 'stat-struct 'mode)
              (if (typep new-value 'mode)
                (mode-bits new-value)
                new-value)))
      (otherwise
        (setf (foreign-slot-value ptr 'stat-struct what) new-value)))))

; Use the new method...
(defsetf stat-get stat-set)

(defun make-stat (&optional (extra nil) &key (size 0))
  "Create a new stat object. 'extra' can be:
a mode object: we copy it to the mode field.
a stat object: we make a copy of it for the new stat object.

Other arguments:
size: initial size for the size field.
"
  (let* ((mem (foreign-alloc 'stat-struct)) ; Allocate memory for a stat
         (obj (make-instance 'stat :ptr mem))) ; Instantiate new object
    ; Don't leak memory.
    (finalize obj (lambda ()
                    (foreign-free mem)))
    (unless (null extra)
      (case (type-of extra)
        (mode
          ; Copy it to the mode field.
          (setf (stat-get obj 'mode)
                (mode-bits extra)))
        (stat
          ; Copy the whole thing.
          (memcpy mem (ptr extra) +stat-size+))))
    ; Optional/Key parameters go here:
    (setf (stat-get obj 'size) size)
    ; Return the new object
    obj))

(defmethod stat-clean ((stat stat))
  "Clean the stat struct, putting zeros there."
  (bzero (ptr stat) (foreign-type-size 'stat-struct)))

(defmethod print-object ((stat stat) stream)
  "Print a stat object."
  (format stream "#<stat: ")
  ; Print the mode object too
  (print-object (stat-get stat 'mode) stream)
  (format stream ">"))

(define-foreign-type stat-type ()
  ()
  (:documentation "CFFI type for stat objects.")
  (:actual-type :pointer)
  (:simple-parser stat-t))

(defmethod translate-to-foreign (stat (type stat-type))
  "Translate a stat object to a foreign pointer."
  (ptr stat))

(defmethod translate-from-foreign (value (type stat-type))
  "Translate a stat pointer to a stat object."
  (make-instance 'stat :ptr value))

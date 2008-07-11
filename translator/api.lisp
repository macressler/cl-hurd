
(in-package :hurd-translator)

(defmacro %add-callback (name args doc &body body)
  "Add a new API classback function."
  `(progn
     (defgeneric ,name (translator ,@args)
                 (:documentation ,doc))
     (defmethod ,name ((translator translator) ,@args)
       ,@(if (null body)
           'nil 
           body))))

(%add-callback make-root-node (underlying-stat)
  "Called when the translator wants to create the root node.
'underlying-stat' refers to the stat structure from the file
where the translator is being set up."
  (make-instance 'node :stat underlying-stat))

(%add-callback pathconf (node user what)
  "This is called when the io-pathconf RPC is called.
'what' refers to the type of information the user wants,
please see common/pathconf.lisp."
	(case what
    ((:link-max :max-canon :max-input
                :pipe-buf :vdisable :sock-maxbuf)
     -1)
    ((:name-max)
     1024)
    ((:chown-restricted :no-trunc)
     1)
    ((:prio-io :sync-io :async-io)
     0)
    (:filesizebits
      32)))

(%add-callback allow-open (node user flags is-new-p)
  "'user' want's to open 'node' with flags 'flags', 'is-new-p' indicates that this is a newly created node. This should return nil when we don't wanna open the node.")

(%add-callback get-translator (node)
  "This must return the translator path that is set under 'node'.")

(%add-callback file-chmod (node user mode)
  "The user is attempting to 'chmod' node with the mode permission bits.")

(%add-callback file-chown (node user uid gid)
  "The user is attempting to 'chown' node with uid and gid.")

(%add-callback file-utimes (node user atime mtime)
  "The user is attempting to change the access and modification time of the node.
'atime' or 'mtime' can be nil.")

(%add-callback dir-lookup (node user filename)
  "This must return the node with the name 'filename' in the directory 'node', nil when it is not found.")

(%add-callback create-file (node user filename mode)
  "The user wants to create a file on the directory 'node' with name 'filename' and mode 'mode'.")

(%add-callback number-of-entries (node user)
  "This must return the number of entries in the directory 'node' from the 'user' point of view."
  0)

(%add-callback get-entries (node user start end)
  "This sould return a list of dirent objects representing the contents of the directory 'node' from 'start' to 'end' (index is zero based).")

(%add-callback allow-author-change (node user author)
  "User wants to change the file's author, return t if it is ok, nil otherwise.")

(%add-callback create-directory (node user name mode)
  "The user wants to create a directory in the directory 'node' with 'name' and 'mode', return nil if don't permitted.")

(%add-callback remove-entry (node user name directory-p)
  "The user wants to remove an entry named 'name' from the directory 'node'. 'directory-p' indicates that the entry is a directory.")

(%add-callback file-read (node user start amount stream)
  "User wants to read 'amount' bytes starting at 'start'. These bytes should be written to the stream 'stream'. Return t in case of success, nil otherwise.")

(%add-callback file-sync (node user wait-p omit-metadata-p)
  "User wants to sync the contents in node. 'wait-p' indicates the user wants to wait. 'omit-metadata-p' indicates we must omit the update of the file metadata (like stat information).")

(%add-callback file-syncfs (user wait-p do-children-p)
  "User wants to sync the entire filesystem. 'wait-p' indicates the user wants to wait for it. 'do-children-p' indicates we should also sync the children nodes."
  t)

(%add-callback file-write (node user offset stream)
  "The user wants to write the bytes in the input stream 'stream' starting at 'offset'.")

(%add-callback drop-node (node)
  "The 'node' has no more references, drop it."
  (warn "Dropped node ~s" node)
  nil)

(%add-callback report-access (node user)
  "This should return a list of permitted access modes for 'user'.Permitted modes are:
:read :write :exec."
  nil)

(%add-callback refresh-statfs (user)
  "The statfs translator field must be updated for 'user'.
Return t for success, nil for unsupported operation."
  nil)

(%add-callback file-change-size (node user new-size)
  "The user wants to change node size to 'new-size'.
Return t on success, nil for unsupported operation."
  nil)

(defmacro define-callback (name trans-type args &body body)
  "Defines one the api callbacks defined above."
  `(defmethod ,name ((translator ,trans-type) ,@args)
     ,@body))


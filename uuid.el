;;; uuid.el --- Provides uuid generating functions

;; Copyright (C) 2010 Kan-Ru Chen

;; Author: Kan-Ru Chen <koster@debian.org>
;; Created: 08 Nov 2010
;; Keywords: extensions, lisp, tools

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This is a naive implementation of RFC4122 Universally Unique
;; IDentifier generation in elisp.  Currently implemented are UUID v1
;; and v4 generation.  The resolution of the time based UUID is
;; microseconds, which is 10 times of the suggested 100-nanosecond
;; resolution, but should be enough for general usage.

;;; TODO:
;;
;; * Implement version 3 and version 5 UUID generation.

;;; Code:

(require 'sha1)

(defvar uuid-unix-epoch-delta #x01b21dd213814000
  "The interval between the UUID epoch and the Unix epoch.
That is the number of 100-nanoseconds between
1582-10-15 00:00:00 and 1970-01-01 00:00:00.")

(defvar uuid-interface "eth0"
  "The default interface for time based UUID generation.")

;; Predefined namespace IDs
;; Ref: RFC4122 Appendix C

(defvar uuid-ns-dns "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
  "For UUID name string which is a fully-qualified domain name.")

(defvar uuid-ns-url "6ba7b811-9dad-11d1-80b4-00c04fd430c8"
  "For UUID name string which is a URL.")

(defvar uuid-ns-oid "6ba7b812-9dad-11d1-80b4-00c04fd430c8"
  "For UUID name string which is an ISO OID.")

(defvar uuid-ns-x500 "6ba7b814-9dad-11d1-80b4-00c04fd430c8"
  "For UUID name string which is an X.500 DN (in DER or a text output format).")

(defun uuid-string-to-octets (string &optional start)
  "Convert UUID string to a list of integers.
STRING should contain a UUID string, the 8-4-4-4-12 format is
preferred.  If START is not nil, start search form START
position."
  (if (string-match "[0-9a-f]\\{2\\}" string start)
      (cons (string-to-number (match-string 0 string) 16)
            (uuid-string-to-octets string (match-end 0)))))

(defun uuid-decode (id)
  "Convert UUID string to binary representation.
ID should contain a UUID string, the 8-4-4-4-12 format is
preferred."
  (eval (cons 'unibyte-string (uuid-string-to-octets id))))

(defun uuid-current-unix-clock ()
  "Get the current Unix time as a 100-nanosecond intervals."
  (let* ((unix-time (current-time))
         (high (first unix-time))
         (low (second unix-time))
         (micro (third unix-time)))
    (+ (* 10000000 (+ (lsh high 16) low))
       (* 10 micro))
    ))

(defun uuid-system-clock ()
  "Get the 100-nanosecond intervals after UUID epoch."
  (+ (uuid-current-unix-clock) uuid-unix-epoch-delta))

(defun uuid-format-time-low (clock)
  "Format the time_low part of the UUID.
CLOCK should be a integer less than 60 bits."
  (format "%08x" (logand #xFFFFFFFF clock)))

(defun uuid-format-time-mid (clock)
  "Format the time_mid part of the UUID.
CLOCK should be a integer less than 60 bits."
  (format "%04x" (logand #xFFFF (lsh clock -32))))

(defun uuid-format-time-hi-version (clock &optional ver)
  "Format the time_hi_and_version part of the UUID.
CLOCK should be a integer less than 60 bits.
VER is the UUID variant number.  Valid VER are 1, 3, 4, 5."
  (let ((version (or ver 1)))
    (format "%04x" (logior (lsh (logand #xF version) 12)
                           (logand #xFFF (lsh clock -48))))))

(defun uuid-format-clock-seq-low (clock)
  "Format the clock_seq_low part of the UUID.
CLOCK should be a integer less than 60 bits."
  (format "%02x" (logand #xFF clock)))

(defun uuid-format-clock-seq-hi-reserved (clock)
  "Format the clock_seq_hi_and_reserved part of the UUID.
CLOCK should be a integer less than 60 bits."
  (format "%02x" (logior #x80 (logand #x3F (lsh clock -8)))))

(defun uuid-get-random-address ()
  "Return a address formed by list of random numbers."
  (mapcar (lambda (n) (random 256)) (make-list 6 0)))

(defun uuid-get-interface (interfaces &optional default)
  "Return the interface for UUID node information.
The INTERFACES is the same format of `network-interface-list' output.
If DEFAULT is not nil, check whether interface DEFAULT exists first."
  (if (and default (network-interface-info default))
      default
    (let ((ifname (caar interfaces)))
      (if (string= ifname "lo")
          (uuid-get-interface (cdr interfaces))
        ifname))))

(defun uuid-get-ieee-address ()
  "Return the IEEE address from `network-interface-info'.
The return value is a array consist of the address number.
If there is no interface available then return a random
multicast address list."
  (let ((info (network-interface-info
               (uuid-get-interface
                (network-interface-list) uuid-interface))))
    (if info
        (cdr (nth 3 info))
      (let ((addr (uuid-get-random-address)))
        ;; Set multicast bit. RFC4122#4.1.6
        (cons (logior #x10 (car addr))
              (cdr addr))))))

(defun uuid-format-ieee-address ()
  "Format the IEEE address based node name of UUID."
  (let ((address (uuid-get-ieee-address)))
    (mapconcat (lambda (var) (format "%02x" var))
               address "")
    ))

(defun uuid-format-random-address ()
  "Format the IEEE address based node name of UUID."
  (let ((address (uuid-get-random-address)))
    (mapconcat (lambda (var) (format "%02x" var))
               address "")
    ))

(defun uuid-gen (clock seq ver addr-function)
  "Generate UUID based on various value.
CLOCK should be a integer less than 60 bits.  SEQ should be a
integer less than 14 bits.  VER is the UUID variant number.
Valid VER are 1, 3, 4, 5.  ADDR-FUNCTION is a function generating
the node information.  Pre-defined ADDR-FUNCTION are
`uuid-format-ieee-address' and `uuid-format-random-address'."
  (concat (uuid-format-time-low clock)
          "-"
          (uuid-format-time-mid clock)
          "-"
          (uuid-format-time-hi-version clock ver)
          "-"
          (uuid-format-clock-seq-hi-reserved seq)
          (uuid-format-clock-seq-low seq)
          "-"
          (funcall addr-function)))

(defun uuid-1 ()
  "Generate time based UUID, aka UUIDv1."
  (let ((clock (uuid-system-clock))
        (seq (random)))
    (uuid-gen clock seq 1 'uuid-format-ieee-address)))

(defun uuid-4 ()
  "Generate UUID form random numbers, aka UUIDv4."
  (let ((clock (random))
        (seq (random)))
    (uuid-gen clock seq 4 'uuid-format-random-address)))

(defalias 'uuid 'uuid-1)

(defun uuid-from-hash (hash ver)
  "Generate name based UUID form hash HASH and version VER."
  (concat (substring hash 0 8)
          "-"
          (substring hash 8 12)
          "-"
          (number-to-string ver)
          (substring hash 13 16)
          "-"
          (format "%04x"
                  (logior #x8000 (logand #x3FFF
                                      (string-to-number (substring hash 16 20) 16))))
          "-"
          (substring hash 20 32)
          ))

(defun uuid-3 (ns name)
  "Generate name based UUID using MD5 hash algorithm, aka UUIDv3.
NS should be a generated UUID or predefined namespaces,
`uuid-ns-dns', `uuid-ns-url', `uuid-ns-oid', `uuid-ns-x500'.
NAME is the node name string."
  (let ((hash (md5 (concat (uuid-decode ns) name))))
    (uuid-from-hash hash 3)))

(defun uuid-5 (ns name)
  "Generate name based UUID using SHA-1 hash algorithm, aka UUIDv5.
NS should be a generated UUID or predefined namespaces,
`uuid-ns-dns', `uuid-ns-url', `uuid-ns-oid', `uuid-ns-x500'.
NAME is the node name string."
  (let ((hash (sha1 (concat (uuid-decode ns) name))))
    (uuid-from-hash hash 5)))

(defun uuid-urn (uuid)
  "Return the string representation of a UUID as a URN."
  (concat "urn:uuid:" uuid))

(provide 'uuid)
;;; uuid.el ends here
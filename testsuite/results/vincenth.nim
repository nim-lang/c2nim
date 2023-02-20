type
  foo* {.bycopy.} = object
    x*: cint
    y*: cint
    z*: cint


##  C11 init syntax:

let lookup*: array[2, foo] = [0: (x: 1, y: 3, z: 4), 1: (x: 2, y: 3, z: 4)]

type
  message_type* = enum
    MESSAGE_TYPE_NOTICE, MESSAGE_TYPE_PRIVMSG, MESSAGE_TYPE_COUNT


let cmdname*: array[MESSAGE_TYPE_COUNT, cstring] = [
    MESSAGE_TYPE_PRIVMSG: "PRIVMSG", MESSAGE_TYPE_NOTICE: "NOTICE"]

const
  EFI_FIRMWARE_VENDOR* = "INTEL"
  EFI_FIRMWARE_MAJOR_REVISION* = 12
  EFI_FIRMWARE_MINOR_REVISION* = 33
  EFI_FIRMWARE_REVISION* = (
    (EFI_FIRMWARE_MAJOR_REVISION shl 16) or (EFI_FIRMWARE_MINOR_REVISION))

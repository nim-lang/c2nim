type

  rosidl_message_typesupport_handle_function* = proc (
      a1: ptr rosidl_message_type_support_t; a2: cstring): ptr rosidl_message_type_support_t ##
                              ##  Copyright 2015-2016 Open Source Robotics Foundation, Inc.
                              ##
                              ##  Licensed under the Apache License, Version 2.0 (the "License");
                              ##  you may not use this file except in compliance with the License.
                              ##  You may obtain a copy of the License at
                              ##
                              ##      http://www.apache.org/licenses/LICENSE-2.0
                              ##
                              ##  Unless required by applicable law or agreed to in writing, software
                              ##  distributed under the License is distributed on an "AS IS" BASIS,
                              ##  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
                              ##  See the License for the specific language governing permissions and
                              ##  limitations under the License.

  rosidl_message_type_support_t* {.importc: "rosidl_message_type_support_t",
                                  header: "message_type_support_struct.h", bycopy.} = object ##
                              ##  Contains rosidl message type support data
    typesupport_identifier* {.importc: "typesupport_identifier".}: cstring ##
                              ##  String identifier for the type_support.
    data* {.importc: "data".}: pointer ##  Pointer to the message type support library
    `func`* {.importc: "func".}: rosidl_message_typesupport_handle_function ##
                              ##  Pointer to the message type support handler function


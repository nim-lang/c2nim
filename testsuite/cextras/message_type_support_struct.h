// Copyright 2015-2016 Open Source Robotics Foundation, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


typedef struct rosidl_message_type_support_t rosidl_message_type_support_t;

typedef const rosidl_message_type_support_t * (* rosidl_message_typesupport_handle_function)(
  const rosidl_message_type_support_t *, const char *);

/// Contains rosidl message type support data
struct rosidl_message_type_support_t
{
  /// String identifier for the type_support.
  const char * typesupport_identifier;
  /// Pointer to the message type support library
  const void * data;
  /// Pointer to the message type support handler function
  rosidl_message_typesupport_handle_function func;
};


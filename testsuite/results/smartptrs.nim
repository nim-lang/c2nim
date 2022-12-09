##
##  Copyright (c) 2008-2014 the Urho3D project.
##
##  Permission is hereby granted, free of charge, to any person obtaining a copy
##  of this software and associated documentation files (the "Software"), to deal
##  in the Software without restriction, including without limitation the rights
##  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
##  copies of the Software, and to permit persons to whom the Software is
##  furnished to do so, subject to the following conditions:
##
##  The above copyright notice and this permission notice shall be included in
##  all copies or substantial portions of the Software.
##
##  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
##  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
##  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
##  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
##  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
##  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
##  THE SOFTWARE.
##

import
  RefCounted

##  Shared pointer template class with intrusive reference counting.

type
  SharedPtr*[T] {.bycopy.} = object ##  Construct a null shared pointer.
                                ##  Prevent direct assignment from a shared pointer of another type.


proc constructSharedPtr*[T](): SharedPtr[T] {.constructor.}
proc constructSharedPtr*[T](rhs: SharedPtr[T]): SharedPtr[T] {.constructor.}
proc constructSharedPtr*[T](`ptr`: ptr T): SharedPtr[T] {.constructor.}
proc destroySharedPtr*[T](this: var SharedPtr[T])
proc `->`*[T](this: SharedPtr[T]): ptr T {.noSideEffect.}
proc `*`*[T](this: SharedPtr[T]): var T {.noSideEffect.}
proc `[]`*[T](this: var SharedPtr[T]; index: cint): var T
proc `<`*[T](this: SharedPtr[T]; rhs: SharedPtr[T]): bool {.noSideEffect.}
proc `==`*[T](this: SharedPtr[T]; rhs: SharedPtr[T]): bool {.noSideEffect.}
proc Reset*[T](this: var SharedPtr[T])
proc Detach*[T](this: var SharedPtr[T])
proc StaticCast*[T; U](this: var SharedPtr[T]; rhs: SharedPtr[U])
proc DynamicCast*[T; U](this: var SharedPtr[T]; rhs: SharedPtr[U])
proc Null*[T](this: SharedPtr[T]): bool {.noSideEffect.}
proc NotNull*[T](this: SharedPtr[T]): bool {.noSideEffect.}
proc Get*[T](this: SharedPtr[T]): ptr T {.noSideEffect.}
proc Refs*[T](this: SharedPtr[T]): cint {.noSideEffect.}
proc WeakRefs*[T](this: SharedPtr[T]): cint {.noSideEffect.}
proc RefCountPtr*[T](this: SharedPtr[T]): ptr RefCount {.noSideEffect.}
proc ToHash*[T](this: SharedPtr[T]): cuint {.noSideEffect.}
##  Perform a static cast from one shared pointer type to another.

proc StaticCast*[T; U](`ptr`: SharedPtr[U]): SharedPtr[T] =
  discard

##  Perform a dynamic cast from one weak pointer type to another.

proc DynamicCast*[T; U](`ptr`: SharedPtr[U]): SharedPtr[T] =
  discard

##  Weak pointer template class with intrusive reference counting. Does not keep the object pointed to alive.

type
  WeakPtr*[T] {.bycopy.} = object ##  Construct a null weak pointer.
                              ##  Prevent direct assignment from a weak pointer of different type.
    ##  Pointer to the RefCount structure.


proc constructWeakPtr*[T](): WeakPtr[T] {.constructor.}
proc constructWeakPtr*[T](rhs: WeakPtr[T]): WeakPtr[T] {.constructor.}
proc constructWeakPtr*[T](rhs: SharedPtr[T]): WeakPtr[T] {.constructor.}
proc constructWeakPtr*[T](`ptr`: ptr T): WeakPtr[T] {.constructor.}
proc destroyWeakPtr*[T](this: var WeakPtr[T])
proc Lock*[T](this: WeakPtr[T]): SharedPtr[T] {.noSideEffect.}
proc Get*[T](this: WeakPtr[T]): ptr T {.noSideEffect.}
proc `->`*[T](this: WeakPtr[T]): ptr T {.noSideEffect.}
proc `*`*[T](this: WeakPtr[T]): var T {.noSideEffect.}
proc `[]`*[T](this: var WeakPtr[T]; index: cint): var T
proc `==`*[T](this: WeakPtr[T]; rhs: WeakPtr[T]): bool {.noSideEffect.}
proc `<`*[T](this: WeakPtr[T]; rhs: WeakPtr[T]): bool {.noSideEffect.}
proc Reset*[T](this: var WeakPtr[T])
proc StaticCast*[T; U](this: var WeakPtr[T]; rhs: WeakPtr[U])
proc DynamicCast*[T; U](this: var WeakPtr[T]; rhs: WeakPtr[U])
proc Null*[T](this: WeakPtr[T]): bool {.noSideEffect.}
proc NotNull*[T](this: WeakPtr[T]): bool {.noSideEffect.}
proc Refs*[T](this: WeakPtr[T]): cint {.noSideEffect.}
proc WeakRefs*[T](this: WeakPtr[T]): cint {.noSideEffect.}
proc Expired*[T](this: WeakPtr[T]): bool {.noSideEffect.}
proc RefCountPtr*[T](this: WeakPtr[T]): ptr RefCount {.noSideEffect.}
proc ToHash*[T](this: WeakPtr[T]): cuint {.noSideEffect.}
##  Perform a static cast from one weak pointer type to another.

proc StaticCast*[T; U](`ptr`: WeakPtr[U]): WeakPtr[T] =
  discard

##  Perform a dynamic cast from one weak pointer type to another.

proc DynamicCast*[T; U](`ptr`: WeakPtr[U]): WeakPtr[T] =
  discard

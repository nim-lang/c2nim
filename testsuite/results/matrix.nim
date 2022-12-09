## //////////////////////////////////////////////////////////////////////////
##  Name:         wx/matrix.h
##  Purpose:      wxTransformMatrix class. NOT YET USED
##  Author:       Chris Breeze, Julian Smart
##  Modified by:  Klaas Holwerda
##  Created:      01/02/97
##  RCS-ID:       $Id$
##  Copyright:    (c) Julian Smart, Chris Breeze
##  Licence:      wxWindows licence
## //////////////////////////////////////////////////////////////////////////

## ! headerfiles="matrix.h wx/object.h"

import
  wx/object, wx/math

## ! codefiles="matrix.cpp"
##  A simple 3x3 matrix. This may be replaced by a more general matrix
##  class some day.
##
##  Note: this is intended to be used in wxDC at some point to replace
##  the current system of scaling/translation. It is not yet used.

## :definition
##   A 3x3 matrix to do 2D transformations.
##   It can be used to map data to window coordinates,
##   and also for manipulating your own data.
##   For example drawing a picture (composed of several primitives)
##   at a certain coordinate and angle within another parent picture.
##   At all times m_isIdentity is set if the matrix itself is an Identity matrix.
##   It is used where possible to optimize calculations.

type
  wxTransformMatrix* {.importcpp: "wxTransformMatrix", header: "wxmatrix.h", bycopy.} = object of wxObject[
      string, string[ubyte]]
    m_matrix* {.importc: "m_matrix".}: array[3, array[3, cdouble]]
    m_isIdentity* {.importc: "m_isIdentity".}: bool


proc constructwxTransformMatrix*(): wxTransformMatrix {.constructor,
    importcpp: "wxTransformMatrix(@)", header: "wxmatrix.h".}
proc constructwxTransformMatrix*(mat: wxTransformMatrix): wxTransformMatrix {.
    constructor, importcpp: "wxTransformMatrix(@)", header: "wxmatrix.h".}
proc destroywxTransformMatrix*(this: var wxTransformMatrix) {.
    importcpp: "#.~wxTransformMatrix()", header: "wxmatrix.h".}
proc GetValue*(this: wxTransformMatrix; col: cint; row: cint): cdouble {.noSideEffect,
    importcpp: "GetValue", header: "wxmatrix.h".}
proc SetValue*(this: var wxTransformMatrix; col: cint; row: cint; value: cdouble) {.
    importcpp: "SetValue", header: "wxmatrix.h".}
proc `==`*(this: wxTransformMatrix; mat: wxTransformMatrix): bool {.noSideEffect,
    importcpp: "(# == #)", header: "wxmatrix.h".}
proc `*=`*(this: var wxTransformMatrix; t: cdouble) {.importcpp: "(# *= #)",
    header: "wxmatrix.h".}
proc `/=`*(this: var wxTransformMatrix; t: cdouble) {.importcpp: "(# /= #)",
    header: "wxmatrix.h".}
proc `+=`*(this: var wxTransformMatrix; m: wxTransformMatrix) {.importcpp: "(# += #)",
    header: "wxmatrix.h".}
proc `-=`*(this: var wxTransformMatrix; m: wxTransformMatrix) {.importcpp: "(# -= #)",
    header: "wxmatrix.h".}
proc `*=`*(this: var wxTransformMatrix; m: wxTransformMatrix) {.importcpp: "(# *= #)",
    header: "wxmatrix.h".}
proc `*`*(this: wxTransformMatrix; t: cdouble): wxTransformMatrix {.noSideEffect,
    importcpp: "(# * #)", header: "wxmatrix.h".}
proc `/`*(this: wxTransformMatrix; t: cdouble): wxTransformMatrix {.noSideEffect,
    importcpp: "(# / #)", header: "wxmatrix.h".}
proc `+`*(this: wxTransformMatrix; m: wxTransformMatrix): wxTransformMatrix {.
    noSideEffect, importcpp: "(# + #)", header: "wxmatrix.h".}
proc `-`*(this: wxTransformMatrix; m: wxTransformMatrix): wxTransformMatrix {.
    noSideEffect, importcpp: "(# - #)", header: "wxmatrix.h".}
proc `*`*(this: wxTransformMatrix; m: wxTransformMatrix): wxTransformMatrix {.
    noSideEffect, importcpp: "(# * #)", header: "wxmatrix.h".}
proc `-`*(this: wxTransformMatrix): wxTransformMatrix {.noSideEffect,
    importcpp: "(- #)", header: "wxmatrix.h".}
proc `()`*(this: var wxTransformMatrix; col: cint; row: cint): var cdouble {.
    importcpp: "#(@)", header: "wxmatrix.h".}
proc `()`*(this: wxTransformMatrix; col: cint; row: cint): cdouble {.noSideEffect,
    importcpp: "#(@)", header: "wxmatrix.h".}
proc Invert*(this: var wxTransformMatrix): bool {.importcpp: "Invert",
    header: "wxmatrix.h".}
proc Identity*(this: var wxTransformMatrix): bool {.importcpp: "Identity",
    header: "wxmatrix.h".}
proc IsIdentity*(this: wxTransformMatrix): bool {.inline, noSideEffect.} =
  return m_isIdentity

proc IsIdentity1*(this: wxTransformMatrix): bool {.inline, noSideEffect,
    importcpp: "IsIdentity1", header: "wxmatrix.h".}
proc Scale*(this: var wxTransformMatrix; scale: cdouble): bool {.importcpp: "Scale",
    header: "wxmatrix.h".}
proc Scale*(this: var wxTransformMatrix; xs: cdouble; ys: cdouble; xc: cdouble;
           yc: cdouble): var wxTransformMatrix {.importcpp: "Scale",
    header: "wxmatrix.h".}
proc Mirror*(this: var wxTransformMatrix; x: bool = true; y: bool = false): var wxTransformMatrix[
    cfloat] {.importcpp: "Mirror", header: "wxmatrix.h".}
proc Translate*(this: var wxTransformMatrix; x: cdouble; y: cdouble): bool {.
    importcpp: "Translate", header: "wxmatrix.h".}
proc Rotate*(this: var wxTransformMatrix; angle: cdouble): bool {.importcpp: "Rotate",
    header: "wxmatrix.h".}
proc Rotate*(this: var wxTransformMatrix; r: cdouble; x: cdouble; y: cdouble): var wxTransformMatrix {.
    importcpp: "Rotate", header: "wxmatrix.h".}
proc TransformX*(this: wxTransformMatrix; x: cdouble): cdouble {.inline, noSideEffect,
    importcpp: "TransformX", header: "wxmatrix.h".}
proc TransformY*(this: wxTransformMatrix; y: cdouble): cdouble {.inline, noSideEffect,
    importcpp: "TransformY", header: "wxmatrix.h".}
proc TransformPoint*(this: wxTransformMatrix; x: cdouble; y: cdouble; tx: var cdouble;
                    ty: var cdouble): bool {.noSideEffect,
    importcpp: "TransformPoint", header: "wxmatrix.h".}
proc InverseTransformPoint*(this: wxTransformMatrix; x: cdouble; y: cdouble;
                           tx: var cdouble; ty: var cdouble): bool {.noSideEffect,
    importcpp: "InverseTransformPoint", header: "wxmatrix.h".}
proc Get_scaleX*(this: var wxTransformMatrix): cdouble {.importcpp: "Get_scaleX",
    header: "wxmatrix.h".}
proc Get_scaleY*(this: var wxTransformMatrix): cdouble {.importcpp: "Get_scaleY",
    header: "wxmatrix.h".}
proc GetRotation*(this: var wxTransformMatrix): cdouble {.importcpp: "GetRotation",
    header: "wxmatrix.h".}
proc SetRotation*(this: var wxTransformMatrix; rotation: cdouble) {.
    importcpp: "SetRotation", header: "wxmatrix.h".}
##
## Chris Breeze reported, that
## some functions of wxTransformMatrix cannot work because it is not
## known if he matrix has been inverted. Be careful when using it.
##
##  Transform X value from logical to device
##  warning: this function can only be used for this purpose
##  because no rotation is involved when mapping logical to device coordinates
##  mirror and scaling for x and y will be part of the matrix
##  if you have a matrix that is rotated, eg a shape containing a matrix to place
##  it in the logical coordinate system, use TransformPoint

proc TransformX*(this: wxTransformMatrix; x: cdouble): cdouble {.inline, noSideEffect.} =
  ## normally like this, but since no rotation is involved (only mirror and scale)
  ## we can do without Y -> m_matrix[1]{0] is -sin(rotation angle) and therefore zero
  ## (x * m_matrix[0][0] + y * m_matrix[1][0] + m_matrix[2][0]))
  return if m_isIdentity: x else: (x * m_matrix[0][0] + m_matrix[2][0])

##  Transform Y value from logical to device
##  warning: this function can only be used for this purpose
##  because no rotation is involved when mapping logical to device coordinates
##  mirror and scaling for x and y will be part of the matrix
##  if you have a matrix that is rotated, eg a shape containing a matrix to place
##  it in the logical coordinate system, use TransformPoint

proc TransformY*(this: wxTransformMatrix; y: cdouble): cdouble {.inline, noSideEffect.} =
  ## normally like this, but since no rotation is involved (only mirror and scale)
  ## we can do without X -> m_matrix[0]{1] is sin(rotation angle) and therefore zero
  ## (x * m_matrix[0][1] + y * m_matrix[1][1] + m_matrix[2][1]))
  return if m_isIdentity: y else: (y * m_matrix[1][1] + m_matrix[2][1])

##  Is the matrix the identity matrix?
##  Each operation checks whether the result is still the identity matrix and sets a flag.

proc IsIdentity1*(this: wxTransformMatrix): bool {.inline, noSideEffect.} =
  return wxIsSameDouble(m_matrix[0][0], 1.0) and
      wxIsSameDouble(m_matrix[1][1], 1.0) and
      wxIsSameDouble(m_matrix[2][2], 1.0) and
      wxIsSameDouble(m_matrix[1][0], 0.0) and
      wxIsSameDouble(m_matrix[2][0], 0.0) and
      wxIsSameDouble(m_matrix[0][1], 0.0) and
      wxIsSameDouble(m_matrix[2][1], 0.0) and
      wxIsSameDouble(m_matrix[0][2], 0.0) and
      wxIsSameDouble(m_matrix[1][2], 0.0)

##  Calculates the determinant of a 2 x 2 matrix

proc wxCalculateDet*(a11: cdouble; a21: cdouble; a12: cdouble; a22: cdouble): cdouble {.
    inline.} =
  return a11 * a22 - a12 * a21

type 
  vehicles* = enum 
    boat = 0x00000001, bicycle = 4, bobycar, car = 0x00000010, truck

const 
  ship = boat
  speedboat = boat

const 
  red* = 4
  green* = 2
  blue* = 3

type 
  food* = enum 
    cucumber = 2, bread = 4, chocolate = 6
  numbers* = enum 
    nten = - 10, nnine, nfour = - 4, one = 1, two, three = + 3, four = 4, 
    positivenine = + 9

const 
  toast = bread
  bun = bread

const 
  negativeten = nten
  aliasA = one
  aliasB = nnine

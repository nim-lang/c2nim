when not defined(ONE):
  const
    ONE* = (1)
when not defined(TWO):
  const
    TWO* = (ONE + ONE)
when not defined(THREE):
  const
    THREE* = "THREEEEE"
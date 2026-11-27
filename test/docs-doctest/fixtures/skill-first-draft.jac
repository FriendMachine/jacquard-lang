type Status = | Done | Pending

area : (Int, Int) ->{} Int
area(w, h) = int.mul(w, h)

same-name?(a, b) = text.eq?(a, b)

ready?(n, status) = bool.and(int.lt?(0, n), match status { | Done -> True | Pending -> False })

either?(a, b) = bool.or(a, bool.not(b))

listed?(xs, x) = list.contains?(xs, x, int.eq)

label(n) = text.from-int(n)

first(pair) = match pair { | (a, _) -> a }

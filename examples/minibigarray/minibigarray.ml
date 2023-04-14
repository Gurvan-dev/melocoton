
type bytes
type buf = { data: bytes; mutable used: int; cap : int }
external buf_alloc  : int -> buf                                  = "buf_alloc"
external buf_free   : buf -> unit                                 = "buf_free"
external buf_get    : buf -> int -> char                          = "buf_get"
external buf_upd    : int -> int -> (int -> char) -> buf -> unit  = "buf_upd"

external wrap_compress               : buf -> buf -> bool       = "wrap_compress"
external wrap_max_len  : int -> int               = "wrap_max_len"

let is_compressible (xs: char array) =
  let len = Array.length xs in if len = 0 then false else
  let (inp, outp) = (buf_alloc len, buf_alloc (wrap_max_len len)) in
  buf_upd 0 (len - 1) (fun i -> Array.get xs i) inp;
  let _ = wrap_compress inp outp in let shrank = outp.used < inp.used in
  buf_free inp; buf_free outp; shrank
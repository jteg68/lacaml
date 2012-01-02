(* Create the precision dependent files for the OCaml code.
   Special rules for the C code are implemented in myocamlbuild.ml
 *)

#load "str.cma";;

let lib = "lib"

let substitute fname0 fname1 subs =
  let fh0 = open_in fname0 in
  let fh1 = open_out fname1 in
  try
    while true do
      let l = input_line fh0 in
      let l = List.fold_left (fun l (r,s) -> Str.global_replace r s l) l subs in
      output_string fh1 l;
      output_char fh1 '\n';
    done
  with End_of_file ->
    close_out fh1;
    close_in fh0

(* [derived] is a list of (new_suffix, substitutions).  Returns the
   list of created files. *)
let derived_files path fnames suffix derived =
  let re = Str.regexp("\\([a-zA-Z]+\\)" ^ suffix ^ "$") in
  let derive l fname =
    if Str.string_match re fname 0 then (
      let seed = Str.matched_group 1 fname in
      if seed <> "lacaml" then (
        let fname0 = Filename.concat path fname in
        let derive1 l (new_suffix, subs) =
          let fname1 = seed ^ new_suffix in
          substitute fname0 (Filename.concat path fname1) subs;
          fname1 :: l
        in
        List.fold_left derive1 l derived;
      ) else l
    ) else l in
  Array.fold_left derive [] fnames

let () =
  let fnames = Sys.readdir lib in
  let mods = ref [] in
  let derive ?(add=false) suffix subs =
    let l = derived_files lib fnames suffix subs in
    if add then mods := l :: !mods in

  let r subs = List.map (fun (r,s) -> (Str.regexp r, s)) subs in
  let float32 = r["FPREC", "S";  "Floatxx", "Float32";  "floatxx", "float32"]
  and float64 = r["FPREC", "D";  "Floatxx", "Float64";  "floatxx", "float64"]
  and complex32 = r["CPREC", "C";  "CBPREC", "S";
                    "Floatxx", "Float32";      "floatxx", "float32";
                    "Complexxx", "Complex32";  "complexxx", "complex32"]
  and complex64 = r["CPREC", "Z";  "CBPREC", "D";
                    "Floatxx", "Float64";      "floatxx", "float64";
                    "Complexxx", "Complex64";  "complexxx", "complex64"]
  in
  derive "_SD.mli" [("2_S.mli", float32); ("2_D.mli", float64) ];
  derive "_SD.ml"  [("2_S.ml",  float32); ("2_D.ml", float64) ] ~add:true;
  derive "_CZ.mli" [("2_C.mli", complex32); ("2_Z.mli", complex64)];
  derive "_CZ.ml"  [("2_C.ml",  complex32); ("2_Z.ml",  complex64)] ~add:true;

  let float32 = r ["NPREC", "S";  "NBPREC", "S";
                   "Numberxx", "Float32";  "numberxx", "float32"]
  and float64 = r ["NPREC", "D"; "NBPREC", "D";
                   "Numberxx", "Float64";  "numberxx", "float64"]
  and complex32 = r ["NPREC", "C"; "NBPREC", "S";
                     "Numberxx", "Complex32";  "numberxx", "complex32"]
  and complex64 = r ["NPREC", "Z"; "NBPREC", "D";
                     "Numberxx", "Complex64"; "numberxx", "complex64"]
  in
  derive "_SDCZ.mli" [("4_S.mli", float32);   ("4_D.mli", float64);
                      ("4_C.mli", complex32); ("4_Z.mli", complex64) ];
  derive "_SDCZ.ml"  [("4_S.ml", float32);   ("4_D.ml", float64);
                      ("4_C.ml", complex32); ("4_Z.ml", complex64) ] ~add:true;

  (* Create lacaml.mlpack *)
  let fh = open_out (Filename.concat lib "lacaml.mlpack") in
  output_string fh "Common\n\
                    Utils\n\
                    Float32\n\
                    Float64\n\
                    Complex32\n\
                    Complex64\n\
                    Io\n\
                    Impl\n";
  List.iter (fun m ->
             let m = String.capitalize(Filename.chop_extension m) in
             output_string fh m;
             output_char fh '\n')
            (List.flatten !mods);
  close_out fh


(* lacaml.mli
 ***********************************************************************)

let ocaml_major, ocaml_minor =
  Scanf.sscanf Sys.ocaml_version "%i.%i" (fun v1 v2 -> v1, v2)

let comment_re = Str.regexp "(\\* [^*]+\\*)[ \n\r\t]*"

let input_file ?(comments=true) ?(prefix="") fname =
  let fh = open_in fname in
  let buf = Buffer.create 2048 in
  try
    while true do
      let l = input_line fh in (* or exn *)
      if l <> "" then (Buffer.add_string buf prefix;
                      Buffer.add_string buf l );
      Buffer.add_char buf '\n'
    done;
    assert false
  with End_of_file ->
    close_in fh;
    let buf = Buffer.contents buf in
    if comments then buf
    else Str.global_replace comment_re "" buf


let mli = input_file (Filename.concat lib "lacaml_SDCZ.mli")

let include_re =
  Str.regexp "^\\( *\\)include +\\([A-Za-z0-9]+_[SDCZ]\\|Io\\|Common\\)"
let open_ba_re = Str.regexp " *open Bigarray *[\n\r\t]?"
let prec_re = Str.regexp " *open *\\(Float[0-9]+\\|Complex[0-9]+\\) *[\n\r\t]*"
let real_io_re = Str.regexp "include module type of Real_io"
let complex_io_re = Str.regexp "include module type of Complex_io"

let mli =
  let subst s =
    let prefix = Str.matched_group 1 s in
    let mname = Str.matched_group 2 s in
    let fincl = Filename.concat lib (String.uncapitalize mname ^ ".mli") in
    let m = input_file fincl ~prefix ~comments:false in
    (* "open Bigarray" already present in the main file *)
    let m = Str.global_replace open_ba_re "" m in
    Str.global_replace prec_re "" m in
  let mli = Str.global_substitute include_re subst mli in
  if ocaml_major <= 3 && ocaml_minor <= 11 then
    (* Replace the "module type" not understood before OCaml 3.12 *)
    let mli = Str.global_replace real_io_re
       "val pp_num : Format.formatter -> float -> unit\n    \
	val pp_vec : (float, 'a) Io.pp_vec\n    \
	val pp_mat : (float, 'a) Io.pp_mat" mli in
    Str.global_replace complex_io_re
       "val pp_num : Format.formatter -> Complex.t -> unit\n    \
	val pp_vec : (Complex.t, 'a) Io.pp_vec\n    \
	val pp_mat : (Complex.t, 'a) Io.pp_mat" mli
  else mli


(* Output the resulting interface *)
let () =
  let fh = open_out (Filename.concat lib "lacaml.mli") in
  output_string fh mli;
  close_out fh

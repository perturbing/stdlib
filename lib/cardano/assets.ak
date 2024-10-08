use aiken/collection/dict.{Dict, from_ascending_pairs_with}
use aiken/collection/list
use aiken/crypto.{Blake2b_224, Hash, Script}
use aiken/option

/// Lovelace is now a type wrapper for Int.
pub type Lovelace =
  Int

/// A type-alias for a `PolicyId`. A `PolicyId` is always 28-byte long
pub type PolicyId =
  Hash<Blake2b_224, Script>

/// Ada, the native currency, isn't associated with any `PolicyId` (it's not
/// possible to mint Ada!).
///
/// By convention, it is an empty `ByteArray`.
pub const ada_policy_id = ""

/// A type-alias for 'AssetName`, which are free-form byte-arrays between
/// 0 and 32 bytes.
pub type AssetName =
  ByteArray

/// Ada, the native currency, isn't associated with any `AssetName` (it's not
/// possible to mint Ada!).
///
/// By convention, it is an empty `ByteArray`.
pub const ada_asset_name = ""

/// A multi-asset output `Value`. Contains tokens indexed by [PolicyId](#PolicyId) and [AssetName](#AssetName).
///
/// > [!IMPORTANT]
/// > This type maintain some invariants by construction; in particular, a `Value` will never contain a
/// zero quantity of a particular token.
pub opaque type Value {
  inner: Dict<PolicyId, Dict<AssetName, Int>>,
}

// ## Constructing

/// Construct a `Value` from an asset identifier (i.e. `PolicyId` + `AssetName`)
/// and a given quantity.
pub fn from_asset(
  policy_id: PolicyId,
  asset_name: AssetName,
  quantity: Int,
) -> Value {
  if quantity == 0 {
    zero
  } else {
    let asset =
      dict.empty
        |> dict.insert(asset_name, quantity)
    dict.empty
      |> dict.insert(policy_id, asset)
      |> Value
  }
}

/// Promote an arbitrary list of assets into a `Value`. This function fails
/// (i.e. halt the program execution) if:
///
/// - there's any duplicate amongst `PolicyId`;
/// - there's any duplicate amongst `AssetName`;
/// - the `AssetName` aren't sorted in ascending lexicographic order; or
/// - any asset quantity is null.
///
/// This function is meant to turn arbitrary user-defined `Data` into safe `Value`,
/// while checking for internal invariants.
pub fn from_asset_list(xs: Pairs<PolicyId, Pairs<AssetName, Int>>) -> Value {
  xs
    |> list.foldr(
        dict.empty,
        fn(inner, acc) {
          expect Pair(p, [_, ..] as x) = inner
          x
            |> from_ascending_pairs_with(fn(v) { v != 0 })
            |> dict.insert_with(
                acc,
                p,
                _,
                fn(_, _, _) {
                  fail @"Duplicate policy in the asset list."
                },
              )
        },
      )
    |> Value
}

test from_asset_list_1() {
  let v = from_asset_list([])
  v == zero
}

test from_asset_list_2() fail {
  let v = from_asset_list([Pair(#"33", [])])
  v == zero
}

test from_asset_list_3() fail {
  let v = from_asset_list([Pair(#"33", [Pair(#"", 0)])])
  v != zero
}

test from_asset_list_4() {
  let v = from_asset_list([Pair(#"33", [Pair(#"", 1)])])
  flatten(v) == [(#"33", #"", 1)]
}

test from_asset_list_5() {
  let v = from_asset_list([Pair(#"33", [Pair(#"", 1), Pair(#"33", 1)])])
  flatten(v) == [(#"33", #"", 1), (#"33", #"33", 1)]
}

test from_asset_list_6() fail {
  let v =
    from_asset_list(
      [
        Pair(#"33", [Pair(#"", 1), Pair(#"33", 1)]),
        Pair(#"33", [Pair(#"", 1), Pair(#"33", 1)]),
      ],
    )
  v != zero
}

test from_asset_list_7() fail {
  let v =
    from_asset_list(
      [
        Pair(#"33", [Pair(#"", 1), Pair(#"33", 1)]),
        Pair(#"34", [Pair(#"", 1), Pair(#"", 1)]),
      ],
    )
  v != zero
}

test from_asset_list_8() {
  let v =
    from_asset_list(
      [
        Pair(#"33", [Pair(#"", 1), Pair(#"33", 1)]),
        Pair(#"34", [Pair(#"31", 1)]), Pair(#"35", [Pair(#"", 1)]),
      ],
    )
  flatten(v) == [
    (#"33", #"", 1), (#"33", #"33", 1), (#"34", #"31", 1), (#"35", #"", 1),
  ]
}

test from_asset_list_9() {
  let v =
    from_asset_list(
      [
        Pair(#"35", [Pair(#"", 1)]), Pair(#"33", [Pair(#"", 1), Pair(#"33", 1)]),
        Pair(#"34", [Pair(#"31", 1)]),
      ],
    )
  flatten(v) == [
    (#"33", #"", 1), (#"33", #"33", 1), (#"34", #"31", 1), (#"35", #"", 1),
  ]
}

/// Construct a `Value` from a lovelace quantity.
///
/// Friendly reminder: 1 Ada = 1.000.000 Lovelace
pub fn from_lovelace(quantity: Int) -> Value {
  from_asset(ada_policy_id, ada_asset_name, quantity)
}

/// Construct an empty `Value` with nothing in it.
pub const zero: Value = Value { inner: dict.empty }

// ## Inspecting

/// Check is a `Value` is zero. That is, it has no assets and holds no Ada/Lovelace.
pub fn is_zero(self: Value) -> Bool {
  self == zero
}

/// A specialized version of `quantity_of` for the Ada currency.
pub fn lovelace_of(self: Value) -> Int {
  quantity_of(self, ada_policy_id, ada_asset_name)
}

/// A list of all token policies in that Value with non-zero tokens.
pub fn policies(self: Value) -> List<PolicyId> {
  dict.keys(self.inner)
}

/// Extract the quantity of a given asset.
pub fn quantity_of(
  self: Value,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> Int {
  self.inner
    |> dict.get(policy_id)
    |> option.and_then(dict.get(_, asset_name))
    |> option.or_else(0)
}

/// Get all tokens associated with a given policy.
pub fn tokens(self: Value, policy_id: PolicyId) -> Dict<AssetName, Int> {
  self.inner
    |> dict.get(policy_id)
    |> option.or_else(dict.empty)
}

// ## Combining

/// Add a (positive or negative) quantity of a single token to a assets.
/// This is more efficient than [`merge`](#merge) for a single asset.
pub fn add(
  self: Value,
  policy_id: PolicyId,
  asset_name: AssetName,
  quantity: Int,
) -> Value {
  if quantity == 0 {
    self
  } else {
    let helper =
      fn(_, left, _right) {
        let inner_result =
          dict.insert_with(
            left,
            asset_name,
            quantity,
            fn(_k, ql, qr) {
              let q = ql + qr
              if q == 0 {
                None
              } else {
                Some(q)
              }
            },
          )
        if dict.is_empty(inner_result) {
          None
        } else {
          Some(inner_result)
        }
      }

    Value(
      dict.insert_with(
        self.inner,
        policy_id,
        dict.from_ascending_pairs([Pair(asset_name, quantity)]),
        helper,
      ),
    )
  }
}

test add_1() {
  let v =
    zero
      |> add(#"acab", #"beef", 321)
      |> add(#"acab", #"beef", -321)
  v == zero
}

test add_2() {
  let v =
    from_lovelace(123)
      |> add(#"acab", #"beef", 321)
      |> add(#"acab", #"beef", -1 * 321)
  v == from_lovelace(123)
}

test add_3() {
  let v =
    from_lovelace(1)
      |> add(ada_policy_id, ada_asset_name, 2)
      |> add(ada_policy_id, ada_asset_name, 3)
  v == from_lovelace(6)
}

test add_4() {
  let v =
    zero
      |> add(#"acab", #"beef", 0)
  v == zero
}

test add_5() {
  let v =
    zero
      |> add(#"acab", #"beef", 0)
      |> add(#"acab", #"beef", 0)
  v == zero
}

/// Combine two `Value` together.
pub fn merge(left v0: Value, right v1: Value) -> Value {
  Value(
    dict.union_with(
      v0.inner,
      v1.inner,
      fn(_, a0, a1) {
        let result =
          dict.union_with(
            a0,
            a1,
            fn(_, q0, q1) {
              let q = q0 + q1
              if q == 0 {
                None
              } else {
                Some(q)
              }
            },
          )
        if dict.is_empty(result) {
          None
        } else {
          Some(result)
        }
      },
    ),
  )
}

test merge_1() {
  let v1 = from_lovelace(1)
  let v2 = from_lovelace(-1)
  merge(v1, v2) == zero
}

test merge_2() {
  let v1 = from_asset(#"00", #"", 1)
  let v2 = from_asset(#"01", #"", 2)
  let v3 = from_asset(#"02", #"", 3)
  let v =
    from_lovelace(42)
      |> merge(v3)
      |> merge(v1)
      |> merge(v2)

  flatten(v) == [
    (#"", #"", 42), (#"00", #"", 1), (#"01", #"", 2), (#"02", #"", 3),
  ]
}

test merge_3() {
  let v1 = from_asset(#"00", #"", 1)
  let v2 = from_asset(#"00", #"", -1)
  let v3 = from_asset(#"01", #"", 1)

  let v =
    zero
      |> merge(v1)
      |> merge(v2)
      |> merge(v3)

  flatten(v) == [(#"01", #"", 1)]
}

test merge_4() {
  let v1 = from_asset(#"00", #"", 1)
  let v2 = from_asset(#"00", #"", -1)

  merge(v1, v2) == zero
}

test merge_5() {
  let v =
    zero
      |> add(#"acab", #"beef", 0)

  merge(zero, v) == zero
}

/// Negates quantities of all tokens (including Ada) in that `Value`.
///
/// ```
/// v1
///   |> assets.negate
///   |> assets.merge(v1)
///   |> assets.is_zero
/// // True
/// ```
pub fn negate(self: Value) -> Value {
  dict.map(self.inner, fn(_, a) { dict.map(a, fn(_, q) { 0 - q }) })
    |> Value
}

/// Get a `Value` excluding Ada.
pub fn without_lovelace(self: Value) -> Value {
  dict.delete(self.inner, ada_policy_id)
    |> Value
}

test without_lovelace_1() {
  let v = from_lovelace(1000000)
  without_lovelace(v) == zero
}

test without_lovelace_2() {
  let v = from_lovelace(1000000)
  let v2 = from_lovelace(50000000)
  without_lovelace(v) == without_lovelace(v2)
}

test without_lovelace_3() {
  let v =
    from_asset(#"010203", #"040506", 100)
      |> add(ada_policy_id, ada_asset_name, 100000000)
  let v2 = from_asset(#"010203", #"040506", 100)
  without_lovelace(v) == without_lovelace(v2) && without_lovelace(v) == v2
}

// ## Transforming

/// Flatten a `Value` as list of 3-tuple `(PolicyId, AssetName, Quantity)`.
///
/// Handy to manipulate values as uniform lists.
pub fn flatten(self: Value) -> List<(PolicyId, AssetName, Int)> {
  dict.foldr(
    self.inner,
    [],
    fn(policy_id, asset_list, value) {
      dict.foldr(
        asset_list,
        value,
        fn(asset_name, quantity, xs) {
          [(policy_id, asset_name, quantity), ..xs]
        },
      )
    },
  )
}

/// Flatten a `Value` as a list of results, possibly discarding some along the way.
///
/// When the transform function returns `None`, the result is discarded altogether.
pub fn flatten_with(
  self: Value,
  with: fn(PolicyId, AssetName, Int) -> Option<result>,
) -> List<result> {
  dict.foldr(
    self.inner,
    [],
    fn(policy_id, asset_list, value) {
      dict.foldr(
        asset_list,
        value,
        fn(asset_name, quantity, xs) {
          when with(policy_id, asset_name, quantity) is {
            None -> xs
            Some(x) ->
              [x, ..xs]
          }
        },
      )
    },
  )
}

test flatten_with_1() {
  flatten_with(zero, fn(p, a, q) { Some((p, a, q)) }) == []
}

test flatten_with_2() {
  let v =
    zero
      |> add("a", "1", 14)
      |> add("b", "", 42)
      |> add("a", "2", 42)

  flatten_with(
    v,
    fn(p, a, q) {
      if q == 42 {
        Some((p, a))
      } else {
        None
      }
    },
  ) == [("a", "2"), ("b", "")]
}

/// Reduce a value into a single result
///
/// ```
/// assets.zero
///  |> assets.add("a", "1", 10)
///  |> assets.add("b", "2", 20)
///  |> assets.reduce(v, 0, fn(_, _, quantity, acc) { acc + quantity })
/// // 30
/// ```
pub fn reduce(
  self: Value,
  start: result,
  with: fn(PolicyId, AssetName, Int, result) -> result,
) -> result {
  dict.foldr(
    self.inner,
    start,
    fn(policy_id, asset_list, result) {
      dict.foldr(asset_list, result, with(policy_id, _, _, _))
    },
  )
}

test reduce_1() {
  let v =
    zero
      |> add("a", "1", 10)
      |> add("b", "2", 20)
  let result = reduce(v, 0, fn(_, _, quantity, acc) { acc + quantity })
  result == 30
}

test reduce_2() {
  let v =
    zero
      |> add("a", "1", 5)
      |> add("a", "2", 15)
      |> add("b", "", 10)
  let result =
    reduce(
      v,
      [],
      fn(policy_id, asset_name, _, acc) { [(policy_id, asset_name), ..acc] },
    )
  result == [("a", "1"), ("a", "2"), ("b", "")]
}

test reduce_3() {
  let v = zero
  let result = reduce(v, 1, fn(_, _, quantity, acc) { acc + quantity })
  result == 1
}

/// Convert the value into a dictionary of dictionaries.
pub fn to_dict(self: Value) -> Dict<PolicyId, Dict<AssetName, Int>> {
  self.inner
}

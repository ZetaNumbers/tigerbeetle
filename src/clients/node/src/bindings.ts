///////////////////////////////////////////////////////
// This file was auto-generated by node_bindings.zig //
//              Do not manually modify.              //
///////////////////////////////////////////////////////


/**
* See [AccountFlags](https://docs.tigerbeetle.com/reference/accounts#flags)
*/
export enum AccountFlags {
  none = 0,

  /**
  * See [linked](https://docs.tigerbeetle.com/reference/accounts#flagslinked)
  */
  linked = (1 << 0),

  /**
  * See [debits_must_not_exceed_credits](https://docs.tigerbeetle.com/reference/accounts#flagsdebits_must_not_exceed_credits)
  */
  debits_must_not_exceed_credits = (1 << 1),

  /**
  * See [credits_must_not_exceed_debits](https://docs.tigerbeetle.com/reference/accounts#flagscredits_must_not_exceed_debits)
  */
  credits_must_not_exceed_debits = (1 << 2),
}

export enum AccountMutableFlags {
  none = 0,

  locked_credit = (1 << 0),
}

/**
* See [TransferFlags](https://docs.tigerbeetle.com/reference/transfers#flags)
*/
export enum TransferFlags {
  none = 0,

  /**
  * See [linked](https://docs.tigerbeetle.com/reference/transfers#flagslinked)
  */
  linked = (1 << 0),

  /**
  * See [pending](https://docs.tigerbeetle.com/reference/transfers#flagspending)
  */
  pending = (1 << 1),

  /**
  * See [post_pending_transfer](https://docs.tigerbeetle.com/reference/transfers#flagspost_pending_transfer)
  */
  post_pending_transfer = (1 << 2),

  /**
  * See [void_pending_transfer](https://docs.tigerbeetle.com/reference/transfers#flagsvoid_pending_transfer)
  */
  void_pending_transfer = (1 << 3),

  /**
  * See [balancing_debit](https://docs.tigerbeetle.com/reference/transfers#flagsbalancing_debit)
  */
  balancing_debit = (1 << 4),

  /**
  * See [balancing_credit](https://docs.tigerbeetle.com/reference/transfers#flagsbalancing_credit)
  */
  balancing_credit = (1 << 5),

  lock_credit = (1 << 6),
}


/**
* See [Account](https://docs.tigerbeetle.com/reference/accounts/#)
*/
export type Account = {

  /**
  * See [id](https://docs.tigerbeetle.com/reference/accounts/#id)
  */
  id: bigint

  /**
  * See [user_data](https://docs.tigerbeetle.com/reference/accounts/#user_data)
  */
  user_data: bigint

  mutable_flags: number

  /**
  * See [reserved](https://docs.tigerbeetle.com/reference/accounts/#reserved)
  */
  reserved: Buffer

  /**
  * See [ledger](https://docs.tigerbeetle.com/reference/accounts/#ledger)
  */
  ledger: number

  /**
  * See [code](https://docs.tigerbeetle.com/reference/accounts/#code)
  */
  code: number

  /**
  * See [flags](https://docs.tigerbeetle.com/reference/accounts/#flags)
  */
  flags: number

  /**
  * See [debits_pending](https://docs.tigerbeetle.com/reference/accounts/#debits_pending)
  */
  debits_pending: bigint

  /**
  * See [debits_posted](https://docs.tigerbeetle.com/reference/accounts/#debits_posted)
  */
  debits_posted: bigint

  /**
  * See [credits_pending](https://docs.tigerbeetle.com/reference/accounts/#credits_pending)
  */
  credits_pending: bigint

  /**
  * See [credits_posted](https://docs.tigerbeetle.com/reference/accounts/#credits_posted)
  */
  credits_posted: bigint

  /**
  * See [timestamp](https://docs.tigerbeetle.com/reference/accounts/#timestamp)
  */
  timestamp: bigint
}


/**
* See [Transfer](https://docs.tigerbeetle.com/reference/transfers/#)
*/
export type Transfer = {

  /**
  * See [id](https://docs.tigerbeetle.com/reference/transfers/#id)
  */
  id: bigint

  /**
  * See [debit_account_id](https://docs.tigerbeetle.com/reference/transfers/#debit_account_id)
  */
  debit_account_id: bigint

  /**
  * See [credit_account_id](https://docs.tigerbeetle.com/reference/transfers/#credit_account_id)
  */
  credit_account_id: bigint

  /**
  * See [user_data](https://docs.tigerbeetle.com/reference/transfers/#user_data)
  */
  user_data: bigint

  /**
  * See [reserved](https://docs.tigerbeetle.com/reference/transfers/#reserved)
  */
  reserved: bigint

  /**
  * See [pending_id](https://docs.tigerbeetle.com/reference/transfers/#pending_id)
  */
  pending_id: bigint

  /**
  * See [timeout](https://docs.tigerbeetle.com/reference/transfers/#timeout)
  */
  timeout: bigint

  /**
  * See [ledger](https://docs.tigerbeetle.com/reference/transfers/#ledger)
  */
  ledger: number

  /**
  * See [code](https://docs.tigerbeetle.com/reference/transfers/#code)
  */
  code: number

  /**
  * See [flags](https://docs.tigerbeetle.com/reference/transfers/#flags)
  */
  flags: number

  /**
  * See [amount](https://docs.tigerbeetle.com/reference/transfers/#amount)
  */
  amount: bigint

  /**
  * See [timestamp](https://docs.tigerbeetle.com/reference/transfers/#timestamp)
  */
  timestamp: bigint
}


/**
* See [CreateAccountError](https://docs.tigerbeetle.com/reference/operations/create_accounts#)
*/
export enum CreateAccountError {

  /**
  * See [ok](https://docs.tigerbeetle.com/reference/operations/create_accounts#ok)
  */
  ok = 0,

  /**
  * See [linked_event_failed](https://docs.tigerbeetle.com/reference/operations/create_accounts#linked_event_failed)
  */
  linked_event_failed = 1,

  /**
  * See [linked_event_chain_open](https://docs.tigerbeetle.com/reference/operations/create_accounts#linked_event_chain_open)
  */
  linked_event_chain_open = 2,

  /**
  * See [timestamp_must_be_zero](https://docs.tigerbeetle.com/reference/operations/create_accounts#timestamp_must_be_zero)
  */
  timestamp_must_be_zero = 3,

  /**
  * See [reserved_flag](https://docs.tigerbeetle.com/reference/operations/create_accounts#reserved_flag)
  */
  reserved_flag = 4,

  /**
  * See [reserved_field](https://docs.tigerbeetle.com/reference/operations/create_accounts#reserved_field)
  */
  reserved_field = 5,

  /**
  * See [id_must_not_be_zero](https://docs.tigerbeetle.com/reference/operations/create_accounts#id_must_not_be_zero)
  */
  id_must_not_be_zero = 6,

  /**
  * See [id_must_not_be_int_max](https://docs.tigerbeetle.com/reference/operations/create_accounts#id_must_not_be_int_max)
  */
  id_must_not_be_int_max = 7,

  /**
  * See [flags_are_mutually_exclusive](https://docs.tigerbeetle.com/reference/operations/create_accounts#flags_are_mutually_exclusive)
  */
  flags_are_mutually_exclusive = 8,

  /**
  * See [ledger_must_not_be_zero](https://docs.tigerbeetle.com/reference/operations/create_accounts#ledger_must_not_be_zero)
  */
  ledger_must_not_be_zero = 9,

  /**
  * See [code_must_not_be_zero](https://docs.tigerbeetle.com/reference/operations/create_accounts#code_must_not_be_zero)
  */
  code_must_not_be_zero = 10,

  /**
  * See [debits_pending_must_be_zero](https://docs.tigerbeetle.com/reference/operations/create_accounts#debits_pending_must_be_zero)
  */
  debits_pending_must_be_zero = 11,

  /**
  * See [debits_posted_must_be_zero](https://docs.tigerbeetle.com/reference/operations/create_accounts#debits_posted_must_be_zero)
  */
  debits_posted_must_be_zero = 12,

  /**
  * See [credits_pending_must_be_zero](https://docs.tigerbeetle.com/reference/operations/create_accounts#credits_pending_must_be_zero)
  */
  credits_pending_must_be_zero = 13,

  /**
  * See [credits_posted_must_be_zero](https://docs.tigerbeetle.com/reference/operations/create_accounts#credits_posted_must_be_zero)
  */
  credits_posted_must_be_zero = 14,

  /**
  * See [exists_with_different_flags](https://docs.tigerbeetle.com/reference/operations/create_accounts#exists_with_different_flags)
  */
  exists_with_different_flags = 15,

  /**
  * See [exists_with_different_user_data](https://docs.tigerbeetle.com/reference/operations/create_accounts#exists_with_different_user_data)
  */
  exists_with_different_user_data = 16,

  /**
  * See [exists_with_different_ledger](https://docs.tigerbeetle.com/reference/operations/create_accounts#exists_with_different_ledger)
  */
  exists_with_different_ledger = 17,

  /**
  * See [exists_with_different_code](https://docs.tigerbeetle.com/reference/operations/create_accounts#exists_with_different_code)
  */
  exists_with_different_code = 18,

  /**
  * See [exists](https://docs.tigerbeetle.com/reference/operations/create_accounts#exists)
  */
  exists = 19,

  reserved_mutable_flag = 20,
}


/**
* See [CreateTransferError](https://docs.tigerbeetle.com/reference/operations/create_transfers#)
*/
export enum CreateTransferError {

  /**
  * See [ok](https://docs.tigerbeetle.com/reference/operations/create_transfers#ok)
  */
  ok = 0,

  /**
  * See [linked_event_failed](https://docs.tigerbeetle.com/reference/operations/create_transfers#linked_event_failed)
  */
  linked_event_failed = 1,

  /**
  * See [linked_event_chain_open](https://docs.tigerbeetle.com/reference/operations/create_transfers#linked_event_chain_open)
  */
  linked_event_chain_open = 2,

  /**
  * See [timestamp_must_be_zero](https://docs.tigerbeetle.com/reference/operations/create_transfers#timestamp_must_be_zero)
  */
  timestamp_must_be_zero = 3,

  /**
  * See [reserved_flag](https://docs.tigerbeetle.com/reference/operations/create_transfers#reserved_flag)
  */
  reserved_flag = 4,

  /**
  * See [reserved_field](https://docs.tigerbeetle.com/reference/operations/create_transfers#reserved_field)
  */
  reserved_field = 5,

  /**
  * See [id_must_not_be_zero](https://docs.tigerbeetle.com/reference/operations/create_transfers#id_must_not_be_zero)
  */
  id_must_not_be_zero = 6,

  /**
  * See [id_must_not_be_int_max](https://docs.tigerbeetle.com/reference/operations/create_transfers#id_must_not_be_int_max)
  */
  id_must_not_be_int_max = 7,

  /**
  * See [flags_are_mutually_exclusive](https://docs.tigerbeetle.com/reference/operations/create_transfers#flags_are_mutually_exclusive)
  */
  flags_are_mutually_exclusive = 8,

  /**
  * See [debit_account_id_must_not_be_zero](https://docs.tigerbeetle.com/reference/operations/create_transfers#debit_account_id_must_not_be_zero)
  */
  debit_account_id_must_not_be_zero = 9,

  /**
  * See [debit_account_id_must_not_be_int_max](https://docs.tigerbeetle.com/reference/operations/create_transfers#debit_account_id_must_not_be_int_max)
  */
  debit_account_id_must_not_be_int_max = 10,

  /**
  * See [credit_account_id_must_not_be_zero](https://docs.tigerbeetle.com/reference/operations/create_transfers#credit_account_id_must_not_be_zero)
  */
  credit_account_id_must_not_be_zero = 11,

  /**
  * See [credit_account_id_must_not_be_int_max](https://docs.tigerbeetle.com/reference/operations/create_transfers#credit_account_id_must_not_be_int_max)
  */
  credit_account_id_must_not_be_int_max = 12,

  /**
  * See [accounts_must_be_different](https://docs.tigerbeetle.com/reference/operations/create_transfers#accounts_must_be_different)
  */
  accounts_must_be_different = 13,

  /**
  * See [pending_id_must_be_zero](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_id_must_be_zero)
  */
  pending_id_must_be_zero = 14,

  /**
  * See [pending_id_must_not_be_zero](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_id_must_not_be_zero)
  */
  pending_id_must_not_be_zero = 15,

  /**
  * See [pending_id_must_not_be_int_max](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_id_must_not_be_int_max)
  */
  pending_id_must_not_be_int_max = 16,

  /**
  * See [pending_id_must_be_different](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_id_must_be_different)
  */
  pending_id_must_be_different = 17,

  /**
  * See [timeout_reserved_for_pending_transfer](https://docs.tigerbeetle.com/reference/operations/create_transfers#timeout_reserved_for_pending_transfer)
  */
  timeout_reserved_for_pending_transfer = 18,

  /**
  * See [ledger_must_not_be_zero](https://docs.tigerbeetle.com/reference/operations/create_transfers#ledger_must_not_be_zero)
  */
  ledger_must_not_be_zero = 19,

  /**
  * See [code_must_not_be_zero](https://docs.tigerbeetle.com/reference/operations/create_transfers#code_must_not_be_zero)
  */
  code_must_not_be_zero = 20,

  /**
  * See [amount_must_not_be_zero](https://docs.tigerbeetle.com/reference/operations/create_transfers#amount_must_not_be_zero)
  */
  amount_must_not_be_zero = 21,

  /**
  * See [debit_account_not_found](https://docs.tigerbeetle.com/reference/operations/create_transfers#debit_account_not_found)
  */
  debit_account_not_found = 22,

  /**
  * See [credit_account_not_found](https://docs.tigerbeetle.com/reference/operations/create_transfers#credit_account_not_found)
  */
  credit_account_not_found = 23,

  /**
  * See [accounts_must_have_the_same_ledger](https://docs.tigerbeetle.com/reference/operations/create_transfers#accounts_must_have_the_same_ledger)
  */
  accounts_must_have_the_same_ledger = 24,

  /**
  * See [transfer_must_have_the_same_ledger_as_accounts](https://docs.tigerbeetle.com/reference/operations/create_transfers#transfer_must_have_the_same_ledger_as_accounts)
  */
  transfer_must_have_the_same_ledger_as_accounts = 25,

  /**
  * See [pending_transfer_not_found](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_transfer_not_found)
  */
  pending_transfer_not_found = 26,

  /**
  * See [pending_transfer_not_pending](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_transfer_not_pending)
  */
  pending_transfer_not_pending = 27,

  /**
  * See [pending_transfer_has_different_debit_account_id](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_transfer_has_different_debit_account_id)
  */
  pending_transfer_has_different_debit_account_id = 28,

  /**
  * See [pending_transfer_has_different_credit_account_id](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_transfer_has_different_credit_account_id)
  */
  pending_transfer_has_different_credit_account_id = 29,

  /**
  * See [pending_transfer_has_different_ledger](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_transfer_has_different_ledger)
  */
  pending_transfer_has_different_ledger = 30,

  /**
  * See [pending_transfer_has_different_code](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_transfer_has_different_code)
  */
  pending_transfer_has_different_code = 31,

  /**
  * See [exceeds_pending_transfer_amount](https://docs.tigerbeetle.com/reference/operations/create_transfers#exceeds_pending_transfer_amount)
  */
  exceeds_pending_transfer_amount = 32,

  /**
  * See [pending_transfer_has_different_amount](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_transfer_has_different_amount)
  */
  pending_transfer_has_different_amount = 33,

  /**
  * See [pending_transfer_already_posted](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_transfer_already_posted)
  */
  pending_transfer_already_posted = 34,

  /**
  * See [pending_transfer_already_voided](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_transfer_already_voided)
  */
  pending_transfer_already_voided = 35,

  /**
  * See [pending_transfer_expired](https://docs.tigerbeetle.com/reference/operations/create_transfers#pending_transfer_expired)
  */
  pending_transfer_expired = 36,

  /**
  * See [exists_with_different_flags](https://docs.tigerbeetle.com/reference/operations/create_transfers#exists_with_different_flags)
  */
  exists_with_different_flags = 37,

  /**
  * See [exists_with_different_debit_account_id](https://docs.tigerbeetle.com/reference/operations/create_transfers#exists_with_different_debit_account_id)
  */
  exists_with_different_debit_account_id = 38,

  /**
  * See [exists_with_different_credit_account_id](https://docs.tigerbeetle.com/reference/operations/create_transfers#exists_with_different_credit_account_id)
  */
  exists_with_different_credit_account_id = 39,

  /**
  * See [exists_with_different_pending_id](https://docs.tigerbeetle.com/reference/operations/create_transfers#exists_with_different_pending_id)
  */
  exists_with_different_pending_id = 40,

  /**
  * See [exists_with_different_user_data](https://docs.tigerbeetle.com/reference/operations/create_transfers#exists_with_different_user_data)
  */
  exists_with_different_user_data = 41,

  /**
  * See [exists_with_different_timeout](https://docs.tigerbeetle.com/reference/operations/create_transfers#exists_with_different_timeout)
  */
  exists_with_different_timeout = 42,

  /**
  * See [exists_with_different_code](https://docs.tigerbeetle.com/reference/operations/create_transfers#exists_with_different_code)
  */
  exists_with_different_code = 43,

  /**
  * See [exists_with_different_amount](https://docs.tigerbeetle.com/reference/operations/create_transfers#exists_with_different_amount)
  */
  exists_with_different_amount = 44,

  /**
  * See [exists](https://docs.tigerbeetle.com/reference/operations/create_transfers#exists)
  */
  exists = 45,

  /**
  * See [overflows_debits_pending](https://docs.tigerbeetle.com/reference/operations/create_transfers#overflows_debits_pending)
  */
  overflows_debits_pending = 46,

  /**
  * See [overflows_credits_pending](https://docs.tigerbeetle.com/reference/operations/create_transfers#overflows_credits_pending)
  */
  overflows_credits_pending = 47,

  /**
  * See [overflows_debits_posted](https://docs.tigerbeetle.com/reference/operations/create_transfers#overflows_debits_posted)
  */
  overflows_debits_posted = 48,

  /**
  * See [overflows_credits_posted](https://docs.tigerbeetle.com/reference/operations/create_transfers#overflows_credits_posted)
  */
  overflows_credits_posted = 49,

  /**
  * See [overflows_debits](https://docs.tigerbeetle.com/reference/operations/create_transfers#overflows_debits)
  */
  overflows_debits = 50,

  /**
  * See [overflows_credits](https://docs.tigerbeetle.com/reference/operations/create_transfers#overflows_credits)
  */
  overflows_credits = 51,

  /**
  * See [overflows_timeout](https://docs.tigerbeetle.com/reference/operations/create_transfers#overflows_timeout)
  */
  overflows_timeout = 52,

  /**
  * See [exceeds_credits](https://docs.tigerbeetle.com/reference/operations/create_transfers#exceeds_credits)
  */
  exceeds_credits = 53,

  /**
  * See [exceeds_debits](https://docs.tigerbeetle.com/reference/operations/create_transfers#exceeds_debits)
  */
  exceeds_debits = 54,

  cannot_post_and_void_pending_transfer = 55,

  pending_transfer_cannot_post_or_void_another = 56,

  credit_account_locked = 57,

  cannot_lock_credit_for_non_pending_transfer = 58,
}

export type CreateAccountsError = {
  index: number
  result: CreateAccountError
}

export type CreateTransfersError = {
  index: number
  result: CreateTransferError
}

export enum Operation {
  create_accounts = 128,
  create_transfers = 129,
  lookup_accounts = 130,
  lookup_transfers = 131,
}


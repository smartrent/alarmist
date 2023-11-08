defmodule Alarmist.Rules.Rule do
  @moduledoc """
  Behaviour module for Alarmist alarm rule definitions
  """

  @type rule_definition :: {atom(), atom(), keyword()}
  @type side_effect ::
          {:raise, atom()}
          | {:clear, atom()}
          | {:increment_counter, atom()}
          | {:clear_counter, atom()}
          | {:add_check_interval, pos_integer(), atom()}

  @doc """
  Returns a keyword list of default option values that will be merged into the configured rule options
  """
  @callback default_options() :: keyword()

  @doc """
  Takes in a rule entry that matched the `type_id`.
  Should return `:ok` if the rule is valid, or `{:error, "Human readable failure reason"}` if validation fails.
  """
  @callback validate(rule_definition()) :: :ok | {:error, String.t()}

  @doc """
  Called by the Monitor after `validate/1` on Alarmist startup, should return a map to merge into the Monitor's state
  """
  @callback setup(rule_definition()) :: list(side_effect())

  @doc """
  Called when `:alarm_handler.set_alarm(alarm_name)` is called, can perform a number of side-effect.
  See `Alarmist.Rules.Rule.side_effect()` for more information on possible side-effects
  """
  @callback on_set(rule_definition(), map()) :: list(side_effect())

  @doc """
  Called when `:alarm_handler.clear_alarm(alarm_name)` is called, can perform a number of side-effect.
  See `Alarmist.Rules.Rule.side_effect()` for more information on possible side-effects
  """
  @callback on_clear(rule_definition(), map()) :: list(side_effect())

  @doc """
  This function is only called when the Alarmist Monitor process is instructed to check in on the alarm's state.
  This is used for Flapping, Heartbeat, and Check-In alarms only, and is usually called using an interval timer.
  """
  @callback on_check(rule_definition(), map()) :: list(side_effect())
end

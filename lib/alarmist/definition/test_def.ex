defmodule MyTestAlarm do
  @moduledoc false

  use Alarmist.Definition

  defalarm do
    AlarmId1 and AlarmId2
  end
end

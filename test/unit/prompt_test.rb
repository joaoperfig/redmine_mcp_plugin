# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RedmineMcpPluginPromptTest < ActiveSupport::TestCase
  def build_prompt(overrides = {})
    RedmineMcpPlugin::Prompt.new(
      {
        name: 'Enter time',
        machine_name: 'enter_time',
        description: 'Draft a time entry.',
        prompt: 'Record the work.'
      }.merge(overrides)
    )
  end

  def test_a_valid_prompt_saves
    assert build_prompt.save
  end

  def test_machine_name_accepts_lower_case_letters_numbers_and_underscores
    assert build_prompt(machine_name: 'enter_time_2').valid?
  end

  def test_machine_name_rejects_other_characters
    ['Enter_Time', 'enter-time', 'enter time', 'enter.time', 'entrée'].each do |machine_name|
      prompt = build_prompt(machine_name: machine_name)

      assert_not prompt.valid?, "#{machine_name.inspect} must be rejected"
      assert prompt.errors[:machine_name].any?
    end
  end

  def test_machine_name_is_unique
    assert build_prompt.save

    duplicate = build_prompt(name: 'Another prompt')

    assert_not duplicate.valid?
    assert duplicate.errors[:machine_name].any?
  end

  def test_name_and_prompt_are_required_but_description_is_optional
    prompt = build_prompt(name: '', prompt: '', description: '')

    assert_not prompt.valid?
    assert prompt.errors[:name].any?
    assert prompt.errors[:prompt].any?
    assert_empty prompt.errors[:description]
  end
end

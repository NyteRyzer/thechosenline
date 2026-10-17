extends RefCounted
## Checks a deduction attempt: the chosen answer plus the evidence cards the
## player connected to it. Wrong attempts cost nothing and return a hint, so
## the puzzle can always be retried (no softlocks).
##
## Deduction format (data/deductions/*.json):
##   id, title, prompt
##   answers              [{id, text, rebuttal?}]  rebuttal = hint when this answer is picked wrongly
##   correct_answer       answer id
##   required_evidence    evidence that must all be connected
##   optional_evidence    evidence that may also be connected without being wrong
##   hint_missing         shown when required evidence is not all connected
##   hint_irrelevant      shown when unrelated evidence is connected
##   hint_not_found       shown when the player hasn't found the required evidence yet
##   success_dialogue     dialogue id played after solving
##   effects              same effects as interaction rules


## Returns {"correct": bool, "feedback": String}.
static func evaluate(deduction: Dictionary, answer_id: String, connected: Array, owned: Array) -> Dictionary:
	var required: Array = deduction.get("required_evidence", [])
	var allowed: Array = required + deduction.get("optional_evidence", [])

	if answer_id == "":
		return _fail("Choose what you think really happened first.")
	if answer_id != str(deduction.get("correct_answer", "")):
		for answer in deduction.get("answers", []):
			if str(answer.get("id", "")) == answer_id and answer.has("rebuttal"):
				return _fail(str(answer.rebuttal))
		return _fail("The evidence doesn't support that.")
	for evidence_id in required:
		if not owned.has(evidence_id):
			return _fail(str(deduction.get("hint_not_found", "I haven't found everything I need yet. Keep searching.")))
	for evidence_id in connected:
		if not allowed.has(evidence_id):
			return _fail(str(deduction.get("hint_irrelevant", "One of these clues doesn't belong here.")))
	for evidence_id in required:
		if not connected.has(evidence_id):
			return _fail(str(deduction.get("hint_missing", "Right idea, but I can't prove it yet. Something's missing.")))
	return {"correct": true, "feedback": ""}


static func _fail(text: String) -> Dictionary:
	return {"correct": false, "feedback": text}

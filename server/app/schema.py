"""Wire contract between the Sift iOS client and the parse service.

Every field is required (nullable where it may be absent) so the JSON schema
stays strict-compatible: strict structured outputs reject optional properties.
"""

from typing import List, Literal, Optional

from pydantic import BaseModel, Field

ItemKind = Literal["event", "task", "backlog", "note"]
Frequency = Literal["daily", "weekly", "monthly"]


class Recurrence(BaseModel):
    frequency: Frequency
    # 1 = Sunday ... 7 = Saturday, matching Foundation's Calendar weekday numbering.
    weekdays: Optional[List[int]] = Field(
        description="Weekdays for a weekly rule, 1=Sunday..7=Saturday. Null otherwise."
    )
    day_of_month: Optional[int] = Field(
        description="Day of month (1-31) for a monthly rule. Null otherwise."
    )
    until: Optional[str] = Field(
        description="Last date the rule applies, YYYY-MM-DD, or null for open-ended."
    )


class ParsedItem(BaseModel):
    kind: ItemKind
    title: str = Field(
        description="Short rewritten title in imperative or noun form. Never the raw sentence."
    )
    details: Optional[str] = Field(
        description="Extra context worth keeping, or null if the title says everything."
    )
    start_at: Optional[str] = Field(
        description="Local start datetime for an event, YYYY-MM-DDTHH:MM. Null for non-events."
    )
    duration_minutes: Optional[int] = Field(
        description="Event duration if stated or strongly implied. Null otherwise."
    )
    due_on: Optional[str] = Field(
        description="Due date for a task, YYYY-MM-DD. Null for backlog items and notes."
    )
    soft_date: bool = Field(
        description="True when the date came from vague timing ('sometime next week')."
    )
    day: Optional[str] = Field(
        description="YYYY-MM-DD the note belongs to. Null for anything that is not a note."
    )
    reminder_lead_minutes: Optional[int] = Field(
        description="Per-item reminder override in minutes before, only if explicitly asked for."
    )
    recurrence: Optional[Recurrence] = Field(
        description="Repetition rule if the item repeats. Null for one-off items."
    )
    needs_review: bool = Field(
        description="True when a date, time, or intent was ambiguous enough to be worth a look."
    )


class ParseResult(BaseModel):
    items: List[ParsedItem]


class ParseRequest(BaseModel):
    transcript: str
    now_local: str = Field(description="Client local time as YYYY-MM-DDTHH:MM:SS")
    timezone: str = Field(default="UTC", description="IANA timezone name")


class ParseResponse(BaseModel):
    items: List[ParsedItem]
    transcript: str

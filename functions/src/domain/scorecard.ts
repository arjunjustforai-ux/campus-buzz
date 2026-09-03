import type { PilotConfig, ScorecardBand } from "./types";

export type Band = "red" | "yellow" | "green" | "no_data";

export interface ScorecardRow {
  key: keyof PilotConfig["bands"];
  label: string;
  value: number | null;
  unit: ScorecardBand["unit"];
  band: Band;
  redBelow: number;
  greenAtOrAbove: number;
}

/** A metric is never green unless actual data meets the threshold. `null` = no data. */
export function bandFor(value: number | null, band: ScorecardBand): Band {
  if (value === null || !Number.isFinite(value)) return "no_data";
  if (value < band.red) return "red";
  if (value >= band.green) return "green";
  return "yellow";
}

export interface ScorecardInput {
  registeredStudents: number | null;
  wapPercent: number | null;
  week6Retention: number | null;
  organizersPostingWeekly: number | null;
  rsvpToAttendance: number | null;
  nps: number | null;
  wouldMiss: number | null;
}

const LABELS: Record<keyof PilotConfig["bands"], string> = {
  registeredStudents: "Registered students",
  wapPercent: "Weekly Active Participants",
  week6Retention: "Week 6 retention (participation)",
  organizersPostingWeekly: "Organizers posting weekly",
  rsvpToAttendance: "RSVP → attendance",
  nps: "NPS",
  wouldMiss: "Would miss CampusBuzz",
};

export function buildScorecard(input: ScorecardInput, bands: PilotConfig["bands"]): ScorecardRow[] {
  return (Object.keys(bands) as Array<keyof PilotConfig["bands"]>).map((key) => {
    const band = bands[key];
    const value = input[key];
    return {
      key,
      label: LABELS[key],
      value,
      unit: band.unit,
      band: bandFor(value, band),
      redBelow: band.red,
      greenAtOrAbove: band.green,
    };
  });
}

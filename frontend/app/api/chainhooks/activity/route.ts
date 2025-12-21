const seededActivity = [
  { type: "Deposit", vault: "Focus Fund", amount: "4,200 STX", time: "2h ago" },
  { type: "Withdrawal", vault: "Voyage Buffer", amount: "1,200 STX", time: "1d ago" },
  { type: "Penalty", vault: "Launch Reserve", amount: "300 STX", time: "3d ago" },
  { type: "Deposit", vault: "Launch Reserve", amount: "6,500 STX", time: "1w ago" }
];

export async function GET() {
  return Response.json({ ok: true, activity: seededActivity });
}

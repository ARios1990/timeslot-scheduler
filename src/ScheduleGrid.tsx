import { useState } from 'react';
import { ChevronDown, MapPin } from 'lucide-react';
import { ScheduleRow, Team, Company, TIME_SLOTS, formatTimeAmPm, ACCOUNT_STATUSES } from './types';

interface ScheduleGridProps {
  rows: ScheduleRow[];
  companies: Company[];
  isBooked: (companyId: string, locationId: string | null, day: string, timeSlot: string) => boolean;
  getCompanyTeams: (companyId: string) => Team[];
  onToggle: (companyId: string, locationId: string | null, day: string, timeSlot: string) => void;
  onStatusChange: (companyId: string, status: string) => void;
  canEdit: (companyId: string) => boolean;
  isAdmin: boolean;
  activeDay: string;
}

export function ScheduleGrid({
  rows, companies, isBooked, getCompanyTeams, onToggle, onStatusChange, canEdit, isAdmin, activeDay,
}: ScheduleGridProps) {
  const [editingStatus, setEditingStatus] = useState<string | null>(null);

  if (rows.length === 0) {
    return (
      <div className="text-center py-16 text-gray-400">
        <p className="text-lg">No companies found for this selection.</p>
        <p className="text-sm mt-1">Try adjusting your filters or add companies via the admin panel.</p>
      </div>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse min-w-[1000px]">
        <thead>
          <tr className="bg-gray-50">
            <th className="text-left py-3 px-4 text-xs font-semibold text-gray-500 uppercase tracking-wider border-b border-gray-200 sticky left-0 bg-gray-50 z-10 min-w-[260px]">
              Company / Location
            </th>
            <th className="text-center py-3 px-1 text-xs font-semibold text-gray-500 uppercase tracking-wider border-b border-gray-200 w-24">
              Teams
            </th>
            <th className="text-center py-3 px-1 text-xs font-semibold text-gray-500 uppercase tracking-wider border-b border-gray-200 w-20">
              Status
            </th>
            {TIME_SLOTS.map(ts => (
              <th key={ts} className="py-3 px-0.5 text-xs font-semibold text-gray-500 border-b border-gray-200 text-center min-w-[64px]">
                {formatTimeAmPm(ts)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, idx) => {
            const companyTeamsList = getCompanyTeams(row.companyId);
            const editable = canEdit(row.companyId);
            const company = companies.find(c => c.id === row.companyId);
            const status = company?.account_status || 'Active';
            const isStatusEditing = editingStatus === row.id;
            const primaryTeam = companyTeamsList[0];

            return (
              <tr
                key={row.id}
                className={`${idx % 2 === 0 ? 'bg-white' : 'bg-gray-50/50'} hover:bg-blue-50/30 transition-colors`}
              >
                {/* Company + Location */}
                <td className="py-2 px-4 border-b border-gray-100 sticky left-0 bg-inherit z-10">
                  <div className="flex flex-col">
                    <span className="text-sm font-semibold text-gray-800 leading-tight truncate max-w-[230px]">
                      {row.companyName}
                    </span>
                    <div className="flex items-center gap-1 mt-0.5">
                      {row.locationLabel ? (
                        <span className="text-[11px] text-blue-600 flex items-center gap-0.5">
                          <MapPin size={9} /> {row.locationLabel}
                        </span>
                      ) : row.state ? (
                        <span className="text-[11px] text-gray-500">{row.state}</span>
                      ) : null}
                    </div>
                  </div>
                </td>

                {/* Teams (multiple) */}
                <td className="py-2 px-1 border-b border-gray-100 text-center">
                  {companyTeamsList.length > 0 ? (
                    <div className="flex flex-wrap gap-0.5 justify-center">
                      {companyTeamsList.map(t => (
                        <span key={t.id} className={`text-[9px] font-bold px-1.5 py-0.5 rounded ${getTeamColor(t.abbreviation)}`}>
                          {t.abbreviation}
                        </span>
                      ))}
                    </div>
                  ) : (
                    <span className="text-[9px] text-gray-300">--</span>
                  )}
                </td>

                {/* Status */}
                <td className="py-2 px-1 border-b border-gray-100 text-center">
                  {isAdmin && isStatusEditing ? (
                    <div className="relative">
                      <select
                        defaultValue={status}
                        onChange={e => { onStatusChange(row.companyId, e.target.value); setEditingStatus(null); }}
                        onBlur={() => setEditingStatus(null)}
                        autoFocus
                        className="text-[9px] px-1 py-0.5 border rounded bg-white w-16 focus:outline-none focus:ring-1 focus:ring-blue-400"
                      >
                        {ACCOUNT_STATUSES.map(s => (
                          <option key={s} value={s}>{s}</option>
                        ))}
                      </select>
                    </div>
                  ) : (
                    <button
                      onClick={() => isAdmin && setEditingStatus(row.id)}
                      disabled={!isAdmin}
                      className={`text-[9px] px-1.5 py-0.5 rounded font-medium inline-flex items-center gap-0.5 ${
                        isAdmin ? 'cursor-pointer hover:ring-1 ring-blue-300' : 'cursor-default'
                      } ${getStatusStyle(status)}`}
                    >
                      {status === 'No Longer Working' ? 'NLW' : status}
                      {isAdmin && <ChevronDown size={8} />}
                    </button>
                  )}
                </td>

                {/* Time Slots */}
                {TIME_SLOTS.map(ts => {
                  const booked = isBooked(row.companyId, row.locationId, activeDay, ts);
                  return (
                    <td key={ts} className="py-1 px-0.5 text-center border-b border-gray-100">
                      <button
                        onClick={() => editable && onToggle(row.companyId, row.locationId, activeDay, ts)}
                        disabled={!editable}
                        className={`w-full h-8 rounded text-[8px] font-bold inline-flex items-center justify-center transition-all leading-tight px-0.5 ${
                          booked
                            ? `${getTeamBgColor(primaryTeam?.abbreviation)} shadow-sm`
                            : editable
                              ? 'bg-emerald-50 border border-emerald-200 text-emerald-400 hover:bg-emerald-100 hover:scale-[1.03]'
                              : 'bg-gray-50 border border-gray-150 text-gray-300'
                        } ${editable ? 'cursor-pointer' : 'cursor-default'}`}
                        title={
                          booked
                            ? `${row.companyName}${row.state ? ` - ${row.state}` : ''} (click to unbook)`
                            : editable ? 'Available' : 'View only'
                        }
                      >
                        {booked && (
                          <span className="truncate">
                            {row.state || primaryTeam?.abbreviation || 'X'}
                          </span>
                        )}
                      </button>
                    </td>
                  );
                })}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function getTeamColor(abbr: string): string {
  const colors: Record<string, string> = {
    MRS: 'bg-blue-100 text-blue-700',
    BRL: 'bg-purple-100 text-purple-700',
    TJ: 'bg-orange-100 text-orange-700',
    PHL: 'bg-teal-100 text-teal-700',
    OCTO: 'bg-rose-100 text-rose-700',
    WOO: 'bg-amber-100 text-amber-700',
    SSL: 'bg-cyan-100 text-cyan-700',
    NIC: 'bg-green-100 text-green-700',
  };
  return colors[abbr] || 'bg-gray-100 text-gray-700';
}

function getTeamBgColor(abbr?: string): string {
  const colors: Record<string, string> = {
    MRS: 'bg-blue-500 text-white',
    BRL: 'bg-purple-500 text-white',
    TJ: 'bg-orange-500 text-white',
    PHL: 'bg-teal-500 text-white',
    OCTO: 'bg-rose-500 text-white',
    WOO: 'bg-amber-500 text-white',
    SSL: 'bg-cyan-500 text-white',
    NIC: 'bg-green-500 text-white',
  };
  return colors[abbr || ''] || 'bg-gray-500 text-white';
}

function getStatusStyle(status: string): string {
  switch (status) {
    case 'Active': return 'bg-green-100 text-green-700';
    case 'Pause': return 'bg-yellow-100 text-yellow-700';
    case 'Prospect': return 'bg-blue-100 text-blue-600';
    case 'Hidden': return 'bg-gray-200 text-gray-500';
    case 'No Longer Working': return 'bg-red-100 text-red-600';
    default: return 'bg-gray-100 text-gray-600';
  }
}

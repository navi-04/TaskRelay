import { FilterType } from '../types/todo';

interface FilterButtonsProps {
  currentFilter: FilterType;
  onFilterChange: (filter: FilterType) => void;
  stats: { total: number; active: number; completed: number };
}

export function FilterButtons({ currentFilter, onFilterChange, stats }: FilterButtonsProps) {
  const filters: { type: FilterType; label: string; count: number }[] = [
    { type: 'all', label: 'All', count: stats.total },
    { type: 'active', label: 'Active', count: stats.active },
    { type: 'completed', label: 'Done', count: stats.completed },
  ];

  return (
    <div className="filters">
      {filters.map(({ type, label, count }) => (
        <button
          key={type}
          className={`filter-btn ${currentFilter === type ? 'active' : ''}`}
          onClick={() => onFilterChange(type)}
        >
          {label} ({count})
        </button>
      ))}
    </div>
  );
}

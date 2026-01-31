import { TodoItem as TodoItemType } from '../types/todo';

interface TodoItemProps {
  item: TodoItemType;
  onToggle: (id: string) => void;
  onDelete: (id: string) => void;
}

export function TodoItem({ item, onToggle, onDelete }: TodoItemProps) {
  return (
    <li className={`todo-item ${item.completed ? 'completed' : ''}`}>
      <input
        type="checkbox"
        checked={item.completed}
        onChange={() => onToggle(item.id)}
      />
      <span className="todo-text">{item.text}</span>
      <button 
        className="delete-btn"
        onClick={() => onDelete(item.id)}
        aria-label="Delete todo"
      >
        ×
      </button>
    </li>
  );
}

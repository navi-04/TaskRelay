import { TodoItem } from './TodoItem';
import { TodoItem as TodoItemType } from '../types/todo';

interface TodoListProps {
  items: TodoItemType[];
  onToggle: (id: string) => void;
  onDelete: (id: string) => void;
}

export function TodoList({ items, onToggle, onDelete }: TodoListProps) {
  if (items.length === 0) {
    return <p className="empty-message">No todos yet. Add one above!</p>;
  }

  return (
    <ul className="todo-list">
      {items.map((item) => (
        <TodoItem
          key={item.id}
          item={item}
          onToggle={onToggle}
          onDelete={onDelete}
        />
      ))}
    </ul>
  );
}

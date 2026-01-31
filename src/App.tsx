import { AddTodo } from './components/AddTodo';
import { TodoList } from './components/TodoList';
import { FilterButtons } from './components/FilterButtons';
import { useTodos } from './hooks/useTodos';
import './index.css';

function App() {
  const { todos, filter, setFilter, addTodo, toggleTodo, deleteTodo, stats } = useTodos();

  return (
    <div className="app">
      <h1>Todo List</h1>
      <AddTodo onAdd={addTodo} />
      <FilterButtons 
        currentFilter={filter} 
        onFilterChange={setFilter} 
        stats={stats} 
      />
      <TodoList 
        items={todos} 
        onToggle={toggleTodo} 
        onDelete={deleteTodo} 
      />
    </div>
  );
}

export default App;

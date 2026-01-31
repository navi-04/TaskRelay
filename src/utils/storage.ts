import { TodoItem, Category } from '../types/todo';

const TODOS_KEY = 'todos-app-data';
const CATEGORIES_KEY = 'todos-app-categories';

export const storage = {
  getTodos: (): TodoItem[] => {
    try {
      const data = localStorage.getItem(TODOS_KEY);
      if (!data) return [];
      const parsed = JSON.parse(data);
      return parsed.map((todo: TodoItem) => ({
        ...todo,
        createdAt: new Date(todo.createdAt),
        updatedAt: new Date(todo.updatedAt),
        dueDate: todo.dueDate ? new Date(todo.dueDate) : undefined,
      }));
    } catch {
      return [];
    }
  },

  saveTodos: (todos: TodoItem[]): void => {
    localStorage.setItem(TODOS_KEY, JSON.stringify(todos));
  },

  getCategories: (): Category[] | null => {
    try {
      const data = localStorage.getItem(CATEGORIES_KEY);
      return data ? JSON.parse(data) : null;
    } catch {
      return null;
    }
  },

  saveCategories: (categories: Category[]): void => {
    localStorage.setItem(CATEGORIES_KEY, JSON.stringify(categories));
  },
};

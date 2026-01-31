import { useState, useMemo, useCallback, useEffect } from 'react';
import { TodoItem, FilterType } from '../types/todo';

type Priority = 'low' | 'medium' | 'high';
type SortType = 'newest' | 'oldest' | 'priority' | 'alphabetical';

interface TodoItemExtended extends TodoItem {
  priority: Priority;
  dueDate?: Date;
  notes?: string;
  tags: string[];
}

interface UndoAction {
  type: 'delete' | 'complete' | 'edit';
  item: TodoItemExtended;
  timestamp: number;
}

const STORAGE_KEY = 'todos-app-data';
const UNDO_TIMEOUT = 5000;

function loadFromStorage(): TodoItemExtended[] {
  try {
    const data = localStorage.getItem(STORAGE_KEY);
    if (!data) return [];
    const parsed = JSON.parse(data);
    return parsed.map((todo: any) => ({
      ...todo,
      createdAt: new Date(todo.createdAt),
      dueDate: todo.dueDate ? new Date(todo.dueDate) : undefined,
    }));
  } catch {
    return [];
  }
}

function saveToStorage(todos: TodoItemExtended[]) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(todos));
  } catch {
    // Storage full or unavailable
  }
}

export function useTodos() {
  const [todos, setTodos] = useState<TodoItemExtended[]>(loadFromStorage);
  const [filter, setFilter] = useState<FilterType>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<SortType>('newest');
  const [undoStack, setUndoStack] = useState<UndoAction[]>([]);

  // Persist todos to localStorage
  useEffect(() => {
    saveToStorage(todos);
  }, [todos]);

  // Auto-clear old undo actions
  useEffect(() => {
    const interval = setInterval(() => {
      setUndoStack((prev) =>
        prev.filter((action) => Date.now() - action.timestamp < UNDO_TIMEOUT)
      );
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  const generateId = useCallback(() => {
    return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }, []);

  const addTodo = useCallback((
    text: string,
    options?: { priority?: Priority; dueDate?: Date; tags?: string[] }
  ) => {
    const trimmedText = text.trim();
    if (!trimmedText) return;

    const newTodo: TodoItemExtended = {
      id: generateId(),
      text: trimmedText,
      completed: false,
      createdAt: new Date(),
      priority: options?.priority || 'medium',
      dueDate: options?.dueDate,
      tags: options?.tags || [],
    };
    setTodos((prev) => [newTodo, ...prev]);
  }, [generateId]);

  const toggleTodo = useCallback((id: string) => {
    setTodos((prev) =>
      prev.map((todo) =>
        todo.id === id ? { ...todo, completed: !todo.completed } : todo
      )
    );
  }, []);

  const deleteTodo = useCallback((id: string) => {
    setTodos((prev) => {
      const todoToDelete = prev.find((t) => t.id === id);
      if (todoToDelete) {
        setUndoStack((stack) => [
          ...stack,
          { type: 'delete', item: todoToDelete, timestamp: Date.now() },
        ]);
      }
      return prev.filter((todo) => todo.id !== id);
    });
  }, []);

  const editTodo = useCallback((id: string, updates: Partial<TodoItemExtended>) => {
    setTodos((prev) =>
      prev.map((todo) =>
        todo.id === id ? { ...todo, ...updates } : todo
      )
    );
  }, []);

  const undo = useCallback(() => {
    const lastAction = undoStack[undoStack.length - 1];
    if (!lastAction) return;

    if (lastAction.type === 'delete') {
      setTodos((prev) => [...prev, lastAction.item]);
    }
    setUndoStack((prev) => prev.slice(0, -1));
  }, [undoStack]);

  const reorderTodos = useCallback((fromIndex: number, toIndex: number) => {
    setTodos((prev) => {
      const result = [...prev];
      const [removed] = result.splice(fromIndex, 1);
      result.splice(toIndex, 0, removed);
      return result;
    });
  }, []);

  const clearCompleted = useCallback(() => {
    setTodos((prev) => prev.filter((todo) => !todo.completed));
  }, []);

  const completeAll = useCallback(() => {
    setTodos((prev) => prev.map((todo) => ({ ...todo, completed: true })));
  }, []);

  const duplicateTodo = useCallback((id: string) => {
    const todo = todos.find((t) => t.id === id);
    if (todo) {
      addTodo(todo.text, {
        priority: todo.priority,
        dueDate: todo.dueDate,
        tags: todo.tags,
      });
    }
  }, [todos, addTodo]);

  // Filtering and sorting
  const processedTodos = useMemo(() => {
    let result = [...todos];

    // Apply search filter
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase();
      result = result.filter(
        (todo) =>
          todo.text.toLowerCase().includes(query) ||
          todo.tags.some((tag) => tag.toLowerCase().includes(query))
      );
    }

    // Apply status filter
    switch (filter) {
      case 'active':
        result = result.filter((todo) => !todo.completed);
        break;
      case 'completed':
        result = result.filter((todo) => todo.completed);
        break;
    }

    // Apply sorting
    const priorityOrder = { high: 0, medium: 1, low: 2 };
    switch (sortBy) {
      case 'oldest':
        result.sort((a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime());
        break;
      case 'newest':
        result.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
        break;
      case 'priority':
        result.sort((a, b) => priorityOrder[a.priority] - priorityOrder[b.priority]);
        break;
      case 'alphabetical':
        result.sort((a, b) => a.text.localeCompare(b.text));
        break;
    }

    return result;
  }, [todos, filter, searchQuery, sortBy]);

  const stats = useMemo(() => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    
    return {
      total: todos.length,
      active: todos.filter((t) => !t.completed).length,
      completed: todos.filter((t) => t.completed).length,
      overdue: todos.filter(
        (t) => !t.completed && t.dueDate && new Date(t.dueDate) < today
      ).length,
      dueToday: todos.filter((t) => {
        if (t.completed || !t.dueDate) return false;
        const due = new Date(t.dueDate);
        return due.toDateString() === today.toDateString();
      }).length,
      highPriority: todos.filter((t) => !t.completed && t.priority === 'high').length,
    };
  }, [todos]);

  const canUndo = undoStack.length > 0;

  return {
    todos: processedTodos,
    allTodos: todos,
    filter,
    setFilter,
    searchQuery,
    setSearchQuery,
    sortBy,
    setSortBy,
    addTodo,
    toggleTodo,
    deleteTodo,
    editTodo,
    reorderTodos,
    clearCompleted,
    completeAll,
    duplicateTodo,
    undo,
    canUndo,
    stats,
  };
}

export type { TodoItemExtended, Priority, SortType };

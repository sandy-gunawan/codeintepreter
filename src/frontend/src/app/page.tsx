'use client';

import { useState, useRef, useEffect } from 'react';
import ReactMarkdown from 'react-markdown';
import { uploadFile, sendChat, ChatResponse, UploadResponse } from '@/lib/api';
import FileUpload from '@/components/FileUpload';

// Unique ID generator. crypto.randomUUID() requires secure context (HTTPS).
function genId(): string {
  try {
    return crypto.randomUUID();
  } catch {
    return Date.now().toString(36) + Math.random().toString(36).slice(2);
  }
}

interface Message {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  code?: string | null;
  outputFiles?: ChatResponse['output_files'];
  timestamp: Date;
}

export default function Home() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [sessionId, setSessionId] = useState<string>('');
  const [datasetBlob, setDatasetBlob] = useState<string>('');
  const [uploadedFile, setUploadedFile] = useState<string>('');
  const [activityLog, setActivityLog] = useState<{ time: string; text: string; status: 'done' | 'active' | 'pending' }[]>([]);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const activityEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  useEffect(() => {
    activityEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [activityLog]);

  const addActivity = (text: string, status: 'done' | 'active' | 'pending' = 'active') => {
    const time = new Date().toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });
    setActivityLog((prev) => {
      // Mark previous active items as done
      const updated = prev.map((item) =>
        item.status === 'active' ? { ...item, status: 'done' as const } : item
      );
      return [...updated, { time, text, status }];
    });
  };

  const clearActivity = () => setActivityLog([]);

  const handleFileUpload = async (file: File) => {
    setIsLoading(true);
    clearActivity();
    addActivity(`Uploading ${file.name} (${(file.size / 1024).toFixed(1)} KB)...`);
    try {
      const result: UploadResponse = await uploadFile(file, sessionId || undefined);
      setSessionId(result.session_id);
      setDatasetBlob(result.blob_path);
      setUploadedFile(result.filename);
      addActivity(`File stored in Azure Blob Storage: ${result.blob_path}`);
      addActivity('Ready for questions', 'done');

      setMessages((prev) => [
        ...prev,
        {
          id: genId(),
          role: 'system',
          content: `Dataset uploaded: **${result.filename}** (${(result.size_bytes / 1024).toFixed(1)} KB)`,
          timestamp: new Date(),
        },
      ]);
      clearActivity();
    } catch (err) {
      addActivity(`Upload failed: ${err instanceof Error ? err.message : 'Unknown error'}`, 'done');
      setMessages((prev) => [
        ...prev,
        {
          id: genId(),
          role: 'system',
          content: `Upload failed: ${err instanceof Error ? err.message : 'Unknown error'}`,
          timestamp: new Date(),
        },
      ]);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSend = async () => {
    if (!input.trim() || !datasetBlob || isLoading) return;

    const userMessage: Message = {
      id: genId(),
      role: 'user',
      content: input,
      timestamp: new Date(),
    };
    setMessages((prev) => [...prev, userMessage]);
    const prompt = input;
    setInput('');
    setIsLoading(true);
    clearActivity();

    // Show pipeline steps as they would happen
    addActivity('Received prompt, starting analysis pipeline...');

    // Step 1: Reading data preview
    const step1Timer = setTimeout(() => {
      addActivity('Reading dataset preview from Azure Blob Storage...');
    }, 800);

    // Step 2: Calling LLM
    const step2Timer = setTimeout(() => {
      addActivity('Sending prompt + data preview to Azure OpenAI (gpt-4.1)...');
    }, 2000);

    // Step 3: LLM generating code
    const step3Timer = setTimeout(() => {
      addActivity('LLM generating Python analysis code...');
    }, 4000);

    // Step 4: Sandbox
    const step4Timer = setTimeout(() => {
      addActivity('Creating sandbox pod (Kata VM isolation)...');
    }, 8000);

    // Step 5: Sandbox executing
    const step5Timer = setTimeout(() => {
      addActivity('Sandbox executing Python code on your dataset...');
    }, 15000);

    // Step 6: Waiting for sandbox (if node scale-up needed)
    const step6Timer = setTimeout(() => {
      addActivity('Waiting for execution to complete...');
    }, 30000);

    // Step 7: Long wait message
    const step7Timer = setTimeout(() => {
      addActivity('Still running (sandbox node may be scaling up, this can take 2-3 min on first use)...');
    }, 60000);

    try {
      const response: ChatResponse = await sendChat(prompt, datasetBlob, sessionId);

      // Clear all pending timers
      [step1Timer, step2Timer, step3Timer, step4Timer, step5Timer, step6Timer, step7Timer].forEach(clearTimeout);

      // Show completion steps based on actual response
      if (response.code) {
        addActivity(`Code generated: ${response.code.split('\\n').length} lines of Python`);
      }
      if (response.status === 'completed') {
        addActivity(`Sandbox execution completed successfully`);
        if (response.output_files.length > 0) {
          const fileNames = response.output_files.map((f) => f.path.split('/').pop()).join(', ');
          addActivity(`Output files: ${fileNames}`);
        }
        addActivity('LLM explaining results...');
        addActivity('Analysis complete', 'done');
      } else if (response.status === 'failed') {
        addActivity(`Execution failed: ${response.message}`, 'done');
      } else if (response.status === 'timeout') {
        addActivity('Execution timed out (sandbox may need more time or resources)', 'done');
      }

      const assistantMessage: Message = {
        id: response.execution_id,
        role: 'assistant',
        content: response.explanation || response.message,
        code: response.code,
        outputFiles: response.output_files,
        timestamp: new Date(),
      };
      setMessages((prev) => [...prev, assistantMessage]);
    } catch (err) {
      [step1Timer, step2Timer, step3Timer, step4Timer, step5Timer, step6Timer, step7Timer].forEach(clearTimeout);
      addActivity(`Error: ${err instanceof Error ? err.message : 'Request failed'}`, 'done');
      setMessages((prev) => [
        ...prev,
        {
          id: genId(),
          role: 'system',
          content: `Error: ${err instanceof Error ? err.message : 'Request failed'}`,
          timestamp: new Date(),
        },
      ]);
    } finally {
      setIsLoading(false);
      // Clear activity after a short delay so user can see final state
      setTimeout(() => clearActivity(), 3000);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  return (
    <div className="flex flex-col h-screen max-w-5xl mx-auto">
      {/* Header */}
      <header className="bg-white border-b px-6 py-4 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-gray-800">Code Interpreter</h1>
          <p className="text-sm text-gray-500">Banking Data Analytics Platform</p>
        </div>
        {uploadedFile && (
          <div className="flex items-center gap-2 bg-green-50 text-green-700 px-3 py-1.5 rounded-full text-sm">
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            {uploadedFile}
          </div>
        )}
      </header>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-6 py-4 space-y-4">
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full text-gray-400">
            <svg className="w-16 h-16 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
            </svg>
            <p className="text-lg font-medium">Upload a dataset to get started</p>
            <p className="text-sm">Supported formats: CSV, XLSX</p>
          </div>
        )}

        {messages.map((msg) => (
          <div
            key={msg.id}
            className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}
          >
            <div
              className={`max-w-[80%] rounded-lg px-4 py-3 ${
                msg.role === 'user'
                  ? 'bg-blue-600 text-white'
                  : msg.role === 'system'
                  ? 'bg-gray-100 text-gray-600 text-sm'
                  : 'bg-white border shadow-sm'
              }`}
            >
              {msg.role === 'assistant' ? (
                <div className="prose prose-sm max-w-none">
                  <ReactMarkdown>{msg.content || ''}</ReactMarkdown>

                  {/* Code block */}
                  {msg.code && (
                    <details className="mt-3">
                      <summary className="cursor-pointer text-sm text-gray-500 hover:text-gray-700">
                        View generated code
                      </summary>
                      <pre className="mt-2">
                        <code>{msg.code}</code>
                      </pre>
                    </details>
                  )}

                  {/* Output files (charts) */}
                  {msg.outputFiles && msg.outputFiles.length > 0 && (
                    <div className="mt-3 space-y-2">
                      {msg.outputFiles.map((file) =>
                        file.type === 'image' ? (
                          <img
                            key={file.path}
                            src={file.url}
                            alt={file.path}
                            className="max-w-full rounded border"
                          />
                        ) : (
                          <a
                            key={file.path}
                            href={file.url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="block text-blue-600 hover:underline text-sm"
                          >
                            Download: {file.path.split('/').pop()}
                          </a>
                        )
                      )}
                    </div>
                  )}
                </div>
              ) : (
                <ReactMarkdown>{msg.content}</ReactMarkdown>
              )}
            </div>
          </div>
        ))}

        {isLoading && activityLog.length > 0 && (
          <div className="flex justify-start">
            <div className="bg-white border shadow-sm rounded-lg px-4 py-3 max-w-[80%] w-full">
              <div className="flex items-center gap-2 text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">
                <div className="animate-spin w-3 h-3 border-2 border-blue-500 border-t-transparent rounded-full" />
                Activity Log
              </div>
              <div className="space-y-1 max-h-48 overflow-y-auto font-mono text-xs">
                {activityLog.map((item, i) => (
                  <div key={i} className="flex items-start gap-2">
                    <span className="text-gray-300 shrink-0">{item.time}</span>
                    {item.status === 'active' ? (
                      <span className="text-blue-600 shrink-0 animate-pulse">●</span>
                    ) : item.status === 'done' ? (
                      <span className="text-green-500 shrink-0">✓</span>
                    ) : (
                      <span className="text-gray-300 shrink-0">○</span>
                    )}
                    <span className={item.status === 'active' ? 'text-blue-700' : 'text-gray-500'}>
                      {item.text}
                    </span>
                  </div>
                ))}
                <div ref={activityEndRef} />
              </div>
            </div>
          </div>
        )}

        <div ref={messagesEndRef} />
      </div>

      {/* Upload + Input */}
      <div className="border-t bg-white px-6 py-4">
        {!uploadedFile && <FileUpload onUpload={handleFileUpload} disabled={isLoading} />}

        <div className="flex gap-2 mt-2">
          <textarea
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={
              datasetBlob
                ? 'Ask a question about your data...'
                : 'Upload a dataset first...'
            }
            disabled={!datasetBlob || isLoading}
            className="flex-1 border rounded-lg px-4 py-2 resize-none focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-400"
            rows={2}
          />
          <button
            onClick={handleSend}
            disabled={!input.trim() || !datasetBlob || isLoading}
            className="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors self-end"
          >
            Send
          </button>
        </div>
      </div>
    </div>
  );
}

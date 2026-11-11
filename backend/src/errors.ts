import type { ZodType } from 'zod';

export class HttpError extends Error {
  constructor(
    public statusCode: number,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}

export function parse<T>(schema: ZodType<T>, data: unknown): T {
  const result = schema.safeParse(data);
  if (!result.success) {
    const issue = result.error.issues[0];
    const where = issue?.path.join('.') || 'petición';
    throw new HttpError(400, 'invalid_request', `${where}: ${issue?.message ?? 'no válido'}`);
  }
  return result.data;
}

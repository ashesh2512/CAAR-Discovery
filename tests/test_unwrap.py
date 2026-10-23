import pytest
from parsl import python_app
from parsl.app.errors import RemoteExceptionWrapper

def run_parsl(parsl_func, *args, **kwargs):
    """
    Runs the inner function of a Parsl python_app and handles the result.
    
    Args:
        parsl_func: The Parsl decorated function (PythonApp).
        *args: Positional arguments for the inner function.
        **kwargs: Keyword arguments for the inner function.
        
    Returns:
        The return value of the inner function.
        
    Raises:
        The exception raised by the inner function if it fails.
    """
    # Access the original function via .func
    inner_func = parsl_func.func
    
    try:
        result = inner_func(*args, **kwargs)
        
        # Parsl's .func might still return a RemoteExceptionWrapper 
        # if the execution was wrapped in a way that captures exceptions.
        if isinstance(result, RemoteExceptionWrapper):
            raise result.get_exception()
            
        return result
    except Exception as e:
        # If the result was already a RemoteExceptionWrapper, it's handled above.
        # If the inner_func raised an exception directly, we raise it here.
        if isinstance(e, RemoteExceptionWrapper):
            raise e.get_exception()
        raise e

# --- Test Functions ---

@python_app
def success_func(x, y):
    return x + y

@python_app
def failure_func():
    raise ValueError("Intentional failure")

# --- Tests ---

def test_run_parsl_success():
    result = run_parsl(success_func, 10, 20)
    assert result == 30

def test_run_parsl_failure():
    with pytest.raises(ValueError, match="Intentional failure"):
        run_parsl(failure_func)

def test_run_parsl_with_kwargs():
    result = run_parsl(success_func, x=5, y=5)
    assert result == 10

if __name__ == "__main__":
    # Allow running via python test_unwrap.py
    pytest.main([__file__])
